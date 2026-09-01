import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import '../models/audio_track.dart';
import '../models/transcript_segment.dart';
import '../services/audio_player_service.dart';
import '../services/transcription_service.dart';
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
  final List<TranscriptPart> parts;
  final AudioTrack? track;

  const AppState({
    this.stage = AppStage.idle,
    this.errorMessage,
    this.percent = 0,
    this.phase,
    this.parts = const [],
    this.track,
  });

  AppState copyWith({
    AppStage? stage,
    String? errorMessage,
    int? percent,
    String? phase,
    List<TranscriptPart>? parts,
    AudioTrack? track,
  }) {
    return AppState(
      stage: stage ?? this.stage,
      errorMessage: errorMessage ?? this.errorMessage,
      percent: percent ?? this.percent,
      phase: phase ?? this.phase,
      parts: parts ?? this.parts,
      track: track ?? this.track,
    );
  }
}

class AppStateNotifier extends StateNotifier<AppState> {
  final Ref _ref;

  AppStateNotifier(this._ref) : super(const AppState());

  void reset() => state = const AppState();

  Future<void> processFile(String filePath, String fileName) async {
    final modelName = _ref.read(selectedModelProvider);
    final model = _ref.read(selectedWhisperModelProvider);
    final splitOnWord = _ref.read(splitOnWordProvider);
    final sizeMb = File(filePath).existsSync()
        ? File(filePath).lengthSync() / (1024 * 1024)
        : 0.0;
    debugPrint('[SolutionsScribe] processFile start: file=$fileName '
        'size=${sizeMb.toStringAsFixed(1)} MB model=$modelName');
    final startWall = DateTime.now();

    state = state.copyWith(
      stage: AppStage.processing,
      percent: 0,
      phase: 'Preparing…',
    );

    try {
      final service = _ref.read(transcriptionServiceProvider);

      final result = await service.transcribe(
        audioPath: filePath,
        model: model,
        splitOnWord: splitOnWord,
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

      // just_audio has no first-party Linux implementation, so loading the
      // audio may fail on a Linux dev host. Transcription is the core feature;
      // proceed to the ready state regardless and only log the failure.
      try {
        final audioService = _ref.read(audioPlayerServiceProvider);
        await audioService.loadFile(filePath);
      } catch (e) {
        debugPrint('[SolutionsScribe] audio load failed '
            '(playback unavailable): $e');
      }

      state = state.copyWith(
        stage: AppStage.ready,
        percent: 100,
        phase: null,
        parts: result.parts,
        track: AudioTrack(
          filePath: filePath,
          title: fileName,
          subtitle: 'Local audio',
          duration: result.totalDuration,
        ),
      );
    } catch (e) {
      debugPrint('[SolutionsScribe] processFile FAILED after '
          '${DateTime.now().difference(startWall).inSeconds}s: $e');
      state = state.copyWith(
        stage: AppStage.error,
        errorMessage: e.toString(),
      );
    }
  }
}

final appStateProvider =
    StateNotifierProvider<AppStateNotifier, AppState>((ref) {
  return AppStateNotifier(ref);
});

const availableModels = <String>[
  'tiny',
  'base',
  'small',
  'medium',
];

final selectedModelProvider = StateProvider<String>((ref) => 'base');

final selectedWhisperModelProvider = Provider<WhisperModel>((ref) {
  final name = ref.watch(selectedModelProvider);
  return ref.read(transcriptionServiceProvider).modelFromString(name);
});

final activeSegmentProvider = StateProvider<int>((ref) => -1);
