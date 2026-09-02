import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import '../models/audio_track.dart';
import '../models/transcript_segment.dart';
import '../services/audio_player_service.dart';
import '../services/transcription_service.dart';
import '../utils/audio_file_utils.dart';
import 'settings_provider.dart';

final transcriptionServiceProvider = Provider(
  (ref) => TranscriptionService(),
);

final audioPlayerServiceProvider = Provider<AudioPlayerService>((ref) {
  final service = AudioPlayerService();
  ref.onDispose(service.dispose);
  return service;
});

/// Stable, non-autoDispose stream providers for playback UI. These must be
/// top-level (not created inside build()) so the subscription to media_kit /
/// just_audio persists across widget rebuilds. Creating StreamProviders inline
/// in a build() tears down and re-subscribes on every rebuild — because these
/// audio streams are broadcast and non-replaying, each fresh subscription
/// starts empty, which froze the progress bar, play/pause icon and the active
/// segment highlight.
final audioPositionProvider = StreamProvider<Duration>((ref) {
  return ref.watch(audioPlayerServiceProvider).positionStream;
});

final audioDurationProvider = StreamProvider<Duration?>((ref) {
  return ref.watch(audioPlayerServiceProvider).durationStream;
});

final audioPlayingProvider = StreamProvider<bool>((ref) {
  return ref.watch(audioPlayerServiceProvider).playingStream;
});

enum AppStage { idle, processing, ready, error }

class AppState {
  final AppStage stage;
  final String? errorMessage;
  final int percent;
  final String? phase;

  /// Wall-clock time the current transcription pass began; used to estimate a
  /// time-remaining figure from progress. Null when no pass is running.
  final DateTime? startedAt;

  /// True while a transcription is running in the background after the user
  /// has already reached the transcript/playback screen.
  final bool isTranscribing;

  /// Non-null when a background transcription finished with an error, so the
  /// (still-open) playback screen can surface it without dropping back to the
  /// upload view.
  final String? transcribeError;

  final List<TranscriptPart> parts;
  final AudioTrack? track;

  const AppState({
    this.stage = AppStage.idle,
    this.errorMessage,
    this.percent = 0,
    this.phase,
    this.startedAt,
    this.isTranscribing = false,
    this.transcribeError,
    this.parts = const [],
    this.track,
  });

  AppState copyWith({
    AppStage? stage,
    String? errorMessage,
    int? percent,
    String? phase,
    DateTime? startedAt,
    bool? isTranscribing,
    String? transcribeError,
    List<TranscriptPart>? parts,
    AudioTrack? track,
  }) {
    return AppState(
      stage: stage ?? this.stage,
      errorMessage: errorMessage ?? this.errorMessage,
      percent: percent ?? this.percent,
      phase: phase ?? this.phase,
      startedAt: startedAt ?? this.startedAt,
      isTranscribing: isTranscribing ?? this.isTranscribing,
      transcribeError: transcribeError ?? this.transcribeError,
      parts: parts ?? this.parts,
      track: track ?? this.track,
    );
  }
}

class AppStateNotifier extends StateNotifier<AppState> {
  final Ref _ref;

  AppStateNotifier(this._ref) : super(const AppState());

  void reset() => state = const AppState();

  /// Opens the system file picker and, if an audio file is chosen, processes
  /// it. Shared by the dropzone click handler and the Ctrl/Cmd+O shortcut.
  Future<void> openFileDialog() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedAudioExtensions.toList(),
    );
    if (result.isNotEmpty) {
      processFile(result.first.path!, fileNameFromPath(result.first.path!));
    }
  }

  /// Runs the full transcription pipeline. The user reaches the transcript /
  /// playback screen immediately; the transcription result is applied to
  /// `parts` when it finishes in the background.
  Future<void> processFile(String filePath, String fileName) async {
    final modelName = _ref.read(selectedModelProvider);
    final model = _ref.read(selectedWhisperModelProvider);
    final splitOnWord = _ref.read(splitOnWordProvider);
    final partGapSeconds = _ref.read(partGapSecondsProvider);
    final sizeMb = File(filePath).existsSync()
        ? File(filePath).lengthSync() / (1024 * 1024)
        : 0.0;
    debugPrint('[SolutionsScribe] processFile start: file=$fileName '
        'size=${sizeMb.toStringAsFixed(1)} MB model=$modelName');
    final startWall = DateTime.now();

    // Enter the ready state immediately so the transcript/playback screen
    // appears without waiting on (potentially slow) model download + inference.
    // Transcription continues in the background and populates `parts`.
    Duration loadedDuration = Duration.zero;
    try {
      final audioService = _ref.read(audioPlayerServiceProvider);
      await audioService.loadFile(filePath);
      loadedDuration = audioService.duration;
    } catch (e) {
      // just_audio has no first-party Linux implementation, so loading the
      // audio may fail on a Linux dev host. Playback may be unavailable, but
      // the transcript screen still shows and populates.
      debugPrint('[SolutionsScribe] audio load failed '
          '(playback unavailable): $e');
    }

    state = state.copyWith(
      stage: AppStage.ready,
      percent: 0,
      phase: null,
      startedAt: startWall,
      isTranscribing: true,
      transcribeError: null,
      parts: const [],
      track: AudioTrack(
        filePath: filePath,
        title: fileName,
        subtitle: 'Local audio',
        duration: loadedDuration,
      ),
    );

    // Apply the "show transcript on open" setting to this file: reset any stale
    // visibility from a previous file's header toggle.
    _ref.read(transcriptVisibleProvider.notifier).state =
        _ref.read(showTranscriptByDefaultProvider);

    // Kick off transcription in the background; don't block the UI on it.
    unawaited(_runTranscription(
      filePath,
      fileName,
      model,
      splitOnWord,
      partGapSeconds,
      startWall,
      loadedDuration,
    ));
  }

  Future<void> _runTranscription(
    String filePath,
    String fileName,
    WhisperModel model,
    bool splitOnWord,
    double partGapSeconds,
    DateTime startWall,
    Duration loadedDuration,
  ) async {
    try {
      final service = _ref.read(transcriptionServiceProvider);

      final result = await service.transcribe(
        audioPath: filePath,
        model: model,
        splitOnWord: splitOnWord,
        partGapSeconds: partGapSeconds,
        onPhase: (phase) {
          debugPrint('[SolutionsScribe] phase: $phase');
          state = state.copyWith(phase: phase);
        },
        onProgress: (percent) {
          state = state.copyWith(percent: percent);
        },
      );

      debugPrint('[SolutionsScribe] transcribe complete in '
          '${DateTime.now().difference(startWall).inSeconds}s '
          '(${result.parts.length} parts)');

      // Prefer the real audio duration from the player; fall back to the
      // transcription's total duration if playback wasn't loaded (e.g. Linux).
      final duration = loadedDuration > Duration.zero
          ? loadedDuration
          : result.totalDuration;

      state = state.copyWith(
        isTranscribing: false,
        transcribeError: null,
        parts: result.parts,
        track: state.track?.copyWith(duration: duration),
      );
    } catch (e) {
      debugPrint('[SolutionsScribe] transcription FAILED after '
          '${DateTime.now().difference(startWall).inSeconds}s: $e');
      state = state.copyWith(
        isTranscribing: false,
        transcribeError: e.toString(),
      );
    }
  }
}

final appStateProvider =
    StateNotifierProvider<AppStateNotifier, AppState>((ref) {
  return AppStateNotifier(ref);
});

final selectedWhisperModelProvider = Provider<WhisperModel>((ref) {
  final name = ref.watch(selectedModelProvider);
  return ref.read(transcriptionServiceProvider).modelFromString(name);
});

final activeSegmentProvider = StateProvider<int>((ref) => -1);

/// Whether the transcript list is shown in the transcript view. Hidden via a
/// header toggle so the user can focus on audio/playback only. Initialises from
/// the "show transcript on open" setting and is re-applied each time a file
/// opens (see [AppStateNotifier.processFile]).
final transcriptVisibleProvider = StateProvider<bool>((ref) {
  return ref.watch(showTranscriptByDefaultProvider);
});
