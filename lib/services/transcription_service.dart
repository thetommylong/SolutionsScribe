import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:whisper_ggml/whisper_ggml.dart';
// whisper_ggml does not re-export the TranscribeResult type even though
// WhisperController.transcribe returns it. Import the internal file directly.
// ignore: implementation_imports
import 'package:whisper_ggml/src/models/whisper_result.dart';

import '../models/transcript_segment.dart';
import 'speaker_service.dart';

const String _logTag = '[SolutionsScribe]';

class TranscriptionResult {
  final List<TranscriptPart> parts;
  final Duration totalDuration;

  const TranscriptionResult({
    required this.parts,
    required this.totalDuration,
  });
}

class TranscriptionService {
  final WhisperController _controller = WhisperController();
  final SpeakerService _speakerService = const SpeakerService();
  final List<File> _temporaryFiles = [];

  Future<TranscriptionResult> transcribe({
    required String audioPath,
    required WhisperModel model,
    bool splitOnWord = false,
    void Function(int percent)? onProgress,
    void Function(String phase)? onPhase,
  }) async {
    final startWall = DateTime.now();
    debugPrint('$_logTag transcribe start: model=${model.modelName} '
        'audio=$audioPath');

    await _ensureModelDownloaded(model, onPhase, onProgress);

    // whisper_ggml always writes a `<input>.wav` right next to its input when
    // it converts (WhisperAudioConvert -> whisper.dart). To avoid leaving
    // artifacts beside the user's original file, hand it a pre-converted WAV
    // in the OS temp dir; that also covers non-WAV inputs (mp3/m4a) without a
    // second copy step. The package's own `<tmp>.wav` output stays in temp.
    final tempWav = await _prepareTempWav(audioPath);

    _temporaryFiles.add(tempWav);
    _temporaryFiles.add(File('${tempWav.path}.wav'));

    TranscribeResult? result;
    try {
      onPhase?.call('Transcribing…');
      debugPrint('$_logTag starting native transcription '
          '(ffmpeg convert + whisper inference)');
      result = await _controller.transcribe(
        model: model,
        audioPath: tempWav.path,
        lang: 'en',
        withSegments: true,
        diarize: false,
        splitOnWord: splitOnWord,
        onProgress: (percent) {
          debugPrint('$_logTag whisper progress: $percent%');
          onProgress?.call(percent);
        },
      );
    } catch (e) {
      await _cleanupTempFiles();
      rethrow;
    }

    debugPrint(
        '$_logTag native transcription returned after '
        '${DateTime.now().difference(startWall).inSeconds}s');

    if (result == null) {
      await _cleanupTempFiles();
      throw TranscriptionException(
        'Whisper failed with no result. Check the native log lines '
        '("whisper_..." / "Exception:") above — the most common cause is a '
        'missing model file or a non-16kHz WAV input.',
      );
    }

    var rawSegments = result.transcription.segments ?? const [];
    if (rawSegments.isEmpty) {
      await _cleanupTempFiles();
      throw TranscriptionException('No segments found in audio');
    }

    // Word-level timestamps yield one segment per word, which the transcript
    // view renders as one tile per word ("one word per line"). Merge them back
    // into sentence chunks so each tile reads as a flowing sentence. Segments
    // are treated as words whenever splitOnWord is on.
    if (splitOnWord) {
      rawSegments = groupWordSegments(rawSegments);
    }

    // The temp WAV must stay alive through the speaker pass, so cleanup only
    // happens after parts are built.
    try {
      // Speaker embeddings are purely informational: if they fail we fall back
      // to unlabeled segments rather than failing the whole transcription.
      final speakerIds = await _speakerService.identifySpeakers(
        wavPath: tempWav.path,
        spans: [
          for (final s in rawSegments) SegmentSpan(from: s.fromTs, to: s.toTs),
        ],
        onPhase: onPhase,
        onProgress: onProgress,
      );

      final totalDuration = rawSegments.last.toTs;
      debugPrint('$_logTag parsed ${rawSegments.length} segments, '
          'audio duration ${totalDuration.inSeconds}s');

      return TranscriptionResult(
        parts: _buildParts(rawSegments, _speakerLabels(speakerIds, rawSegments.length)),
        totalDuration: totalDuration,
      );
    } finally {
      await _cleanupTempFiles();
    }
  }

  /// Map per-segment speaker ids to display labels. [ids] may be null (whole
  /// speaker pass failed) or contain null entries (segment too short) — both
  /// yield null labels, which the UI hides entirely.
  List<String?> _speakerLabels(List<int?>? ids, int count) {
    if (ids == null) {
      return List<String?>.filled(count, null);
    }
    return [
      for (var i = 0; i < count; i++)
        i < ids.length && ids[i] != null ? 'Speaker ${ids[i]! + 1}' : null,
    ];
  }

  /// Make sure the .bin model file exists on disk before calling native code.
  /// whisper_ggml @ 2.6.0 does NOT auto-download models: it only loads a
  /// local file and fails hard (with the error swallowed by the plugin) when
  /// that file is missing. We stream it down from HuggingFace ourselves so we
  /// can report progress.
  Future<void> _ensureModelDownloaded(
    WhisperModel model,
    void Function(String phase)? onPhase,
    void Function(int percent)? onProgress,
  ) async {
    final modelPath = await _controller.getPath(model);
    final modelFile = File(modelPath);

    if (modelFile.existsSync()) {
      final mb = modelFile.lengthSync() / (1024 * 1024);
      debugPrint('$_logTag model present: $modelPath (${mb.toStringAsFixed(1)} MB)');
      return;
    }

    debugPrint('$_logTag model MISSING at $modelPath — downloading');
    onPhase?.call('Downloading Whisper model…');
    await _downloadModelWithProgress(model, modelFile, onProgress: (pct) {
      onPhase?.call('Downloading Whisper model… $pct%');
      onProgress?.call(pct);
    });

    final mb = await modelFile.length();
    debugPrint('$_logTag model downloaded: $modelPath '
        '(${(mb / (1024 * 1024)).toStringAsFixed(1)} MB)');
  }

  Future<void> _downloadModelWithProgress(
    WhisperModel model,
    File target, {
    void Function(int percent)? onProgress,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);

    try {
      final request = await client.getUrl(model.modelUri);
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        throw TranscriptionException(
          'Model download failed (HTTP ${response.statusCode}) from '
          '${model.modelUri}',
        );
      }

      final total = response.contentLength;
      debugPrint('$_logTag download start: ${model.modelName} '
          '${(total / (1024 * 1024)).toStringAsFixed(1)} MB '
          '<- ${model.modelUri}');

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
        if (received % (16 * 1024 * 1024) == 0 || received == chunk.length) {
          debugPrint(
            '$_logTag model download: '
            '${(received / (1024 * 1024)).toStringAsFixed(1)} MB of '
            '${(total / (1024 * 1024)).toStringAsFixed(1)} MB',
          );
        }
      }

      await sink.close();
    } catch (e) {
      debugPrint('$_logTag model download FAILED: $e');
      rethrow;
    } finally {
      client.close();
    }
  }

  List<TranscriptPart> _buildParts(
    List<WhisperTranscribeSegment> segments,
    List<String?> speakerLabels,
  ) {
    final parts = <TranscriptPart>[];
    final currentSegments = <TranscriptSegment>[];
    var partIndex = 0;

    for (var i = 0; i < segments.length; i++) {
      final raw = segments[i];

      if (i > 0 && _isNewPart(segments[i - 1], raw)) {
        if (currentSegments.isNotEmpty) {
          parts.add(TranscriptPart(
            index: partIndex++,
            segments: List.unmodifiable(currentSegments),
          ));
          currentSegments.clear();
        }
      }

      currentSegments.add(TranscriptSegment(
        text: raw.text.trim(),
        fromTs: raw.fromTs,
        toTs: raw.toTs,
        speakerLabel: speakerLabels[i],
      ));
    }

    if (currentSegments.isNotEmpty) {
      parts.add(TranscriptPart(
        index: partIndex,
        segments: List.unmodifiable(currentSegments),
      ));
    }

    return parts;
  }

  bool _isNewPart(
    WhisperTranscribeSegment prev,
    WhisperTranscribeSegment current,
  ) {
    final gap = current.fromTs - prev.toTs;
    return gap > const Duration(seconds: 2);
  }

  /// Merge per-word whisper segments into sentence-sized chunks. Each word is
  /// its own [WhisperTranscribeSegment] when `splitOnWord` is on; this groups
  /// them so the transcript reads as sentences. A new group starts on a
  /// sentence-ending word (`.`, `!`, `?`), after a small pause (>300ms), or
  /// once a group reaches [maxWords] as a safety cap.
  static List<WhisperTranscribeSegment> groupWordSegments(
    List<WhisperTranscribeSegment> words,
  ) {
    const maxWords = 20;
    const maxPause = Duration(milliseconds: 300);

    final groups = <WhisperTranscribeSegment>[];
    var buffer = <WhisperTranscribeSegment>[];

    void flush() {
      if (buffer.isEmpty) return;
      final first = buffer.first;
      final last = buffer.last;
      groups.add(WhisperTranscribeSegment(
        text: buffer.map((w) => w.text.trim()).where((t) => t.isNotEmpty).join(' '),
        fromTs: first.fromTs,
        toTs: last.toTs,
      ));
      buffer = [];
    }

    for (final word in words) {
      final text = word.text.trim();
      if (text.isEmpty) continue;
      final isSentenceEnd =
          text.endsWith('.') || text.endsWith('!') || text.endsWith('?');

      // Flush the current group before adding this word if it would exceed the
      // cap or if there's a significant pause since the previous word. The
      // sentence boundary is handled after adding, so the punctuation word
      // stays with the group it completes.
      if (buffer.isNotEmpty &&
          (buffer.length >= maxWords ||
              word.fromTs - buffer.last.toTs > maxPause)) {
        flush();
      }

      buffer.add(word);
      if (isSentenceEnd) {
        flush();
      }
    }
    flush();

    return groups;
  }

  /// Copy/convert [sourcePath] into a 16 kHz mono WAV inside the OS temp
  /// directory. whisper_ggml's converter appends `.wav` to whatever input it
  /// is given, so keeping its input in temp keeps all artifacts in temp.
  ///
  /// - For inputs already in WAV format we copy the bytes as-is; whisper's own
  ///   conversion step is then a no-op reprocess through ffmpeg into `<tmp>.wav`.
  /// - For mp3/m4a we run ffmpeg ourselves so the original never gets a
  ///   sidecar `.<fmt>.wav` written beside it.
  Future<File> _prepareTempWav(String sourcePath) async {
    final ext = sourcePath.split('.').last.toLowerCase();
    final isWav = ext == 'wav';
    final name = 'solutionscribe_${DateTime.now().microsecondsSinceEpoch}';
    final target = File('${Directory.systemTemp.path}${Platform.pathSeparator}$name.wav');

    if (isWav) {
      final source = File(sourcePath);
      await source.copy(target.path);
    } else {
      await _convertToWav(sourcePath, target.path);
    }

    return target;
  }

  Future<void> _convertToWav(String sourcePath, String targetPath) async {
    final result = await Process.run('ffmpeg', [
      '-y',
      '-i',
      sourcePath,
      '-ar',
      '16000',
      '-ac',
      '1',
      '-c:a',
      'pcm_s16le',
      targetPath,
    ]);
    if (result.exitCode != 0) {
      debugPrint('$_logTag ffmpeg convert failed (${result.exitCode}): '
          '${result.stderr}');
      throw TranscriptionException(
        'Failed to convert audio to WAV. Is ffmpeg installed on PATH?',
      );
    }
  }

  Future<void> _cleanupTempFiles() async {
    for (final file in _temporaryFiles) {
      try {
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (e) {
        debugPrint('$_logTag temp cleanup skipped: $e');
      }
    }
    _temporaryFiles.clear();
  }

  WhisperModel modelFromString(String name) {
    switch (name) {
      case 'tiny':
        return WhisperModel.tiny;
      case 'base':
        return WhisperModel.base;
      case 'small':
        return WhisperModel.small;
      case 'medium':
        return WhisperModel.medium;
      default:
        return WhisperModel.base;
    }
  }
}

class TranscriptionException implements Exception {
  final String message;
  const TranscriptionException(this.message);

  @override
  String toString() => 'TranscriptionException: $message';
}