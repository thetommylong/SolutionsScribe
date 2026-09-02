import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

const String _logTag = '[SolutionsScribe]';

/// Sendable payload passed into the speaker-embedding background isolate.
///
/// All fields are plain, isolate-sendable data ([SendPort]s are inherently
/// sendable); no closures or UI objects cross the boundary.
class _IsolateRequest {
  final List<({int fromMicros, int toMicros})> spanTimes;
  final String modelPath;
  final String wavPath;
  final SendPort replyPort;

  const _IsolateRequest({
    required this.spanTimes,
    required this.modelPath,
    required this.wavPath,
    required this.replyPort,
  });
}

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

      // Run the whole embedding pass on a background isolate. The heavy
      // sherpa `compute` FFI calls would otherwise block the UI isolate's
      // native thread; sherpa's docs require calling `initBindings()` inside
      // the isolate that uses it, and in Flutter that falls back to the
      // process's loaded symbols, which is safe across isolates. Only plain
      // data (sample counts / PCM samples / span frame bounds) crosses the
      // boundary; all native sherpa objects live and die inside the isolate.
      final embeddings = await _computeEmbeddingsInIsolate(
        modelPath: modelPath,
        wavPath: wavPath,
        spans: spans,
        onProgress: onProgress,
      );

      if (embeddings == null) {
        debugPrint('$_logTag speaker: readWave returned no usable audio '
            'for $wavPath');
        return null;
      }

      final ids = assignSpeakers(embeddings);
      debugPrint('$_logTag speaker: ${spans.length} segments -> '
          '${_clusterCount(ids)} speaker(s)');
      return ids;
    } catch (e) {
      debugPrint('$_logTag speaker identification failed: $e');
      return null;
    }
  }

  /// Compute every span's embedding inside a background isolate, returning
  /// `null` only if the audio fails to read (all-native work stays off the UI
  /// isolate). The return list is aligned with [spans]; individual entries may
  /// be null when a span is too short to embed reliably.
  ///
  /// The isolate streams an integer progress (0–100) back to [onProgress] as
  /// each span finishes. Because FFI bindings are per-isolate, [onProgress]
  /// cannot be a captured closure (it would bound a non-sendable UI object);
  /// instead we use a real isolate/ReceivePort and forward only sendable ints.
  Future<List<Float32List?>?> _computeEmbeddingsInIsolate({
    required String modelPath,
    required String wavPath,
    required List<SegmentSpan> spans,
    void Function(int percent)? onProgress,
  }) {
    // Only plain, sendable data crosses the isolate boundary: the span time
    // ranges. Frame math happens inside the isolate against the real sample
    // rate of the decoded wave.
    final spanTimes = [
      for (final s in spans)
        (fromMicros: s.from.inMicroseconds, toMicros: s.to.inMicroseconds),
    ];

    final reply = ReceivePort();
    final error = ReceivePort();
    final completer = Completer<List<Float32List?>?>();

    Isolate.spawn(
      _computeEmbeddingsInBackground,
      _IsolateRequest(
        spanTimes: spanTimes,
        modelPath: modelPath,
        wavPath: wavPath,
        replyPort: reply.sendPort,
      ),
      onError: error.sendPort,
      debugName: 'sherpa-speaker-embeddings',
    );

    reply.listen((message) {
      if (message is int) {
        // Incremental progress (0–100).
        onProgress?.call(message);
      } else if (message is List) {
        completer.complete(message.cast<Float32List?>());
      }
    });

    error.listen((message) {
      debugPrint('$_logTag speaker isolate error: $message');
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    });

    return completer.future;
  }

  /// Background-isolate entrypoint for speaker embedding computation. Runs in
  /// its own isolate entirely (fresh FFI bindings, own extractor + streams);
  /// reports percent progress as flat ints to [replyPort] and finishes by
  /// sending the embeddings list (or a null on read failure).
  static void _computeEmbeddingsInBackground(_IsolateRequest request) {
    final replyPort = request.replyPort;
    try {
      // FFI bindings are per-isolate: (re)initialize before touching sherpa.
      // In Flutter this falls back to the process's loaded symbols, which is
      // safe across isolates.
      sherpa_onnx.initBindings();

      final extractor = sherpa_onnx.SpeakerEmbeddingExtractor(
        config: sherpa_onnx.SpeakerEmbeddingExtractorConfig(
          model: request.modelPath,
          numThreads: 1,
          debug: false,
          provider: 'cpu',
        ),
      );

      try {
        final wave = sherpa_onnx.readWave(request.wavPath);
        if (wave.samples.isEmpty || wave.sampleRate <= 0) {
          replyPort.send(null);
          return;
        }

        final sr = wave.sampleRate;
        final sampleCount = wave.samples.length;
        final total = request.spanTimes.length;
        final embeddings = <Float32List?>[];
        for (final t in request.spanTimes) {
          embeddings.add(_embedTimeRange(
            extractor,
            wave.samples,
            sr,
            sampleCount,
            t.fromMicros,
            t.toMicros,
          ));
          final done = embeddings.length;
          replyPort.send(total == 0 ? 100 : (done * 100) ~/ total);
        }
        replyPort.send(embeddings);
      } finally {
        extractor.free();
      }
    } catch (e) {
      debugPrint('$_logTag speaker isolate failed: $e');
      replyPort.send(null);
    }
  }

  /// Extract one embedding from a raw mono float PCM buffer for the sample
  /// range covered by [fromMicros, toMicros) (in the [sampleRate] domain), or
  /// null when the span is too short / out of range / fails to embed.
  static Float32List? _embedTimeRange(
    sherpa_onnx.SpeakerEmbeddingExtractor extractor,
    Float32List samples,
    int sampleRate,
    int sampleCount,
    int fromMicros,
    int toMicros,
  ) {
    final sr = sampleRate;

    int timeToFrame(int micros) =>
        (micros * sr) ~/ Duration.microsecondsPerSecond;

    var start = timeToFrame(fromMicros).clamp(0, sampleCount);
    var end = timeToFrame(toMicros).clamp(0, sampleCount);
    if (end < start) end = start;

    final maxFrames = (maxSpanDuration.inMicroseconds * sr) ~/
        Duration.microsecondsPerSecond;
    end = math.min(end, start + maxFrames);

    final minFrames = (minSpanDuration.inMicroseconds * sr) ~/
        Duration.microsecondsPerSecond;
    if (end - start < minFrames) {
      return null;
    }

    final segment = samples.sublist(start, end);
    final stream = extractor.createStream();
    try {
      stream.acceptWaveform(samples: segment, sampleRate: sr);
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