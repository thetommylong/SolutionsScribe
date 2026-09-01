import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

const String _logTag = '[SolutionsScribe]';

/// A time span we want an embedding for. Aligned to whisper segments.
class SegmentSpan {
  final Duration from;
  final Duration to;

  const SegmentSpan({required this.from, required this.to});

  Duration get duration => to - from;
}

/// On-device speaker diarization for a single transcript.
///
/// Uses sherpa-onnx's speaker embedding extractor (CPU) to compute one
/// embedding per whisper segment, then clusters the embeddings greedily by
/// cosine similarity. The resulting speaker ids are stable within the file but
/// live only in memory for the current session — nothing is persisted.
class SpeakerService {
  const SpeakerService();

  /// Minimum cosine similarity (on L2-normalized embeddings) before a segment
  /// joins an existing speaker cluster; below this a new speaker is created.
  static const double clusterSimilarityThreshold = 0.75;

  /// Segments shorter than this are skipped (too little audio to embed).
  static const Duration minSpanDuration = Duration(milliseconds: 400);

  /// Segments longer than this are truncated to it before embedding; a few
  /// seconds of speech is plenty for a speaker embedding and bounds the cost.
  static const Duration maxSpanDuration = Duration(seconds: 8);

  static const String _modelFileName =
      '3dspeaker_speech_eres2net_sv_en_voxceleb_16k.onnx';
  static const String _modelUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
      'speaker-recongition-models/$_modelFileName';

  /// Compute a speaker id for every span, or `null` if speaker identification
  /// failed entirely (model download, native library or audio decode error).
  ///
  /// The returned list is aligned with [spans]; individual entries may be null
  /// when a span was too short to embed reliably.
  Future<List<int?>?> identifySpeakers({
    required String wavPath,
    required List<SegmentSpan> spans,
    void Function(String phase)? onPhase,
    void Function(int percent)? onProgress,
  }) async {
    try {
      onPhase?.call('Identifying speakers…');
      final modelPath = await _ensureModelDownloaded(onPhase, onProgress);

      await sherpa_onnx.initBindingsAsync();

      final extractor = sherpa_onnx.SpeakerEmbeddingExtractor(
        config: sherpa_onnx.SpeakerEmbeddingExtractorConfig(
          model: modelPath,
          numThreads: 1,
          debug: false,
          provider: 'cpu',
        ),
      );

      try {
        final wave = sherpa_onnx.readWave(wavPath);
        if (wave.samples.isEmpty || wave.sampleRate <= 0) {
          debugPrint('$_logTag speaker: readWave returned empty audio for '
              '$wavPath');
          return null;
        }

        final total = spans.length;
        final embeddings = <Float32List?>[];
        for (var i = 0; i < total; i++) {
          embeddings.add(_embedSpan(extractor, wave, spans[i]));
          final done = i + 1;
          onPhase?.call('Identifying speakers… $done/$total');
          onProgress?.call(total == 0 ? 100 : (done * 100) ~/ total);
          // Let the event loop repaint the progress UI between native calls.
          await Future<void>.delayed(Duration.zero);
        }

        final ids = assignSpeakers(embeddings);
        debugPrint('$_logTag speaker: ${spans.length} segments -> '
            '${_clusterCount(ids)} speaker(s)');
        return ids;
      } finally {
        extractor.free();
      }
    } catch (e) {
      debugPrint('$_logTag speaker identification failed: $e');
      return null;
    }
  }

  /// Extract one embedding for [span] from [wave], or null when the span is
  /// too short / fails to embed. [wave] is mono 16 kHz float PCM.
  Float32List? _embedSpan(
    sherpa_onnx.SpeakerEmbeddingExtractor extractor,
    sherpa_onnx.WaveData wave,
    SegmentSpan span,
  ) {
    final sr = wave.sampleRate;
    final start = _clampFrame(span.from, sr, 0, wave.samples.length);
    var end = _clampFrame(span.to, sr, start, wave.samples.length);
    final maxFrames =
        (maxSpanDuration.inMicroseconds * sr) ~/ Duration.microsecondsPerSecond;
    end = math.min(end, start + maxFrames);

    final minFrames =
        (minSpanDuration.inMicroseconds * sr) ~/ Duration.microsecondsPerSecond;
    if (end - start < minFrames) {
      return null;
    }

    final samples = wave.samples.sublist(start, end);
    final stream = extractor.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sr);
      stream.inputFinished();
      if (!extractor.isReady(stream)) {
        return null;
      }
      final embedding = extractor.compute(stream);
      return embedding.isEmpty ? null : embedding;
    } finally {
      stream.free();
    }
  }

  int _clampFrame(Duration time, int sampleRate, int min, int max) {
    final frame = (time.inMicroseconds * sampleRate) ~/
        Duration.microsecondsPerSecond;
    return frame.clamp(min, max).toInt();
  }

  /// Greedy agglomerative clustering over [embeddings] by cosine similarity.
  ///
  /// Iterates in order and assigns each embedding to the best existing
  /// cluster when their cosine similarity reaches [threshold]; otherwise a new
  /// cluster is started. Cluster ids follow first-appearance order, so the
  /// returned "Speaker 1/2/…" numbering is deterministic for a given file.
  ///
  /// Pure Dart — kept separate from the native calls so it can be unit tested
  /// without sherpa-onnx.
  @visibleForTesting
  static List<int?> assignSpeakers(
    List<Float32List?> embeddings, {
    double threshold = clusterSimilarityThreshold,
  }) {
    final mounts = <List<double>>[];
    final counts = <int>[];
    final result = List<int?>.filled(embeddings.length, null);

    for (var i = 0; i < embeddings.length; i++) {
      final raw = embeddings[i];
      if (raw == null || raw.isEmpty) {
        continue;
      }

      final normalized = _normalize(raw);
      var bestIndex = -1;
      var bestSimilarity = threshold;
      for (var c = 0; c < mounts.length; c++) {
        final sim = _dot(normalized, mounts[c]);
        if (sim > bestSimilarity) {
          bestSimilarity = sim;
          bestIndex = c;
        }
      }

      if (bestIndex == -1) {
        mounts.add(normalized);
        counts.add(1);
        result[i] = mounts.length - 1;
      } else {
        final centroid = mounts[bestIndex];
        final n = counts[bestIndex];
        for (var d = 0; d < centroid.length; d++) {
          centroid[d] = (centroid[d] * n + normalized[d]) / (n + 1);
        }
        counts[bestIndex] = n + 1;
        _renormalizeInPlace(centroid);
        result[i] = bestIndex;
      }
    }

    return result;
  }

  static List<double> _normalize(Float32List v) {
    var norm = 0.0;
    for (final x in v) {
      norm += x * x;
    }
    norm = math.sqrt(norm);
    if (norm == 0) {
      return List<double>.filled(v.length, 0);
    }
    return [for (final x in v) x / norm];
  }

  static void _renormalizeInPlace(List<double> v) {
    var norm = 0.0;
    for (final x in v) {
      norm += x * x;
    }
    norm = math.sqrt(norm);
    if (norm == 0) {
      return;
    }
    for (var i = 0; i < v.length; i++) {
      v[i] = v[i] / norm;
    }
  }

  static double _dot(List<double> a, List<double> b) {
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  static int? _clusterCount(List<int?> ids) {
    final set = <int>{};
    for (final id in ids) {
      if (id != null) set.add(id);
    }
    return set.isEmpty ? null : set.length;
  }

  /// Stream the small English speaker-embedding model from the sherpa-onnx
  /// release into `appSupport/speaker` if it isn't cached yet.
  Future<String> _ensureModelDownloaded(
    void Function(String phase)? onPhase,
    void Function(int percent)? onProgress,
  ) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}${Platform.pathSeparator}speaker');
    await dir.create(recursive: true);
    final modelFile = File('${dir.path}${Platform.pathSeparator}$_modelFileName');

    if (modelFile.existsSync() && modelFile.lengthSync() > 0) {
      return modelFile.path;
    }

    debugPrint('$_logTag speaker model missing at ${modelFile.path} — '
        'downloading $_modelFileName');
    onPhase?.call('Downloading speaker model…');
    await _downloadWithProgress(modelFile, onProgress: (pct) {
      onProgress?.call(pct);
    });

    debugPrint('$_logTag speaker model downloaded: '
        '${(await modelFile.length() / (1024 * 1024)).toStringAsFixed(1)} MB');
    return modelFile.path;
  }

  Future<void> _downloadWithProgress(
    File target, {
    void Function(int percent)? onProgress,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);

    try {
      final request = await client.getUrl(Uri.parse(_modelUrl));
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        throw SpeakerException(
          'Speaker model download failed (HTTP ${response.statusCode}) '
          'from $_modelUrl',
        );
      }

      final total = response.contentLength;
      await target.parent.create(recursive: true);
      final sink = target.openWrite();
      var received = 0;

      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final pct = ((received * 100) ~/ total).clamp(0, 100);
          onProgress?.call(pct);
        }
      }

      await sink.close();
    } finally {
      client.close();
    }
  }
}

class SpeakerException implements Exception {
  final String message;
  const SpeakerException(this.message);

  @override
  String toString() => 'SpeakerException: $message';
}