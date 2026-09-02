import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// Publishes SolutionsScribe playback to the operating system's media session
/// (macOS Now Playing / Control Center / Touch Bar, Windows SMTC) and receives
/// transport commands from it.
///
/// This handler owns the `just_audio` [AudioPlayer] that backs the
/// macOS/Windows playback path. It forwards play/pause/seek/skip/stop from the
/// OS media UI into that player, and streams the player's position/duration/
/// playing state back out as a [PlaybackState] plus a current [MediaItem] so
/// the OS shows the track title and a live scrubber.
///
/// The handler is Linux-agnostic: on Linux the app keeps its `media_kit` (mpv)
/// backend and never initializes audio_service, so playback there is entirely
/// unaffected.
class SolutionsAudioHandler extends BaseAudioHandler {
  final AudioPlayer _player;

  SolutionsAudioHandler() : _player = AudioPlayer() {
    // Push position + playback state to the OS as it changes.
    _listenToPlayer();
  }

  void _listenToPlayer() {
    // Position updates (per tick) reflected into playbackState.updatePosition.
    _player.positionStream
        .listen((position) => _emitPlaybackState(position: position));

    // Playing flag drives the OS play/pause affordance + state.
    _player.playingStream
        .listen((playing) => _emitPlaybackState(playing: playing));

    // Duration -> mediaItem duration, once known.
    _player.durationStream.listen((duration) {
      final item = mediaItem.value;
      if (item != null && duration != null) {
        mediaItem.add(item.copyWith(duration: duration));
      }
    });
  }

  void _emitPlaybackState({
    Duration? position,
    bool? playing,
  }) {
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        _player.playing
            ? MediaControl.pause
            : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.ready,
      playing: playing ?? _player.playing,
      updatePosition: position ?? _player.position,
      speed: 1.0,
    ));
  }

  /// Loads [filePath] into the player and advertises it to the OS as the
  /// current [MediaItem].
  Future<void> loadFile(String filePath, {required String title}) async {
    await _player.setFilePath(filePath);
    mediaItem.add(MediaItem(
      id: filePath,
      title: title,
      artist: 'SolutionsScribe',
      album: 'Local audio',
      duration: _player.duration,
    ));
    _emitPlaybackState();
  }

  // --- Receiving transport commands from the OS ---

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    _emitPlaybackState(position: Duration.zero, playing: false);
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    await _player.stop();
    await _player.seek(Duration.zero);
  }

  @override
  Future<void> skipToPrevious() async {
    await _player.stop();
    await _player.seek(Duration.zero);
  }

  // --- App-side playback surface ---

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;

  Duration get position => _player.position;
  Duration get duration => _player.duration ?? Duration.zero;
  bool get playing => _player.playing;

  Future<void> playPause() {
    if (_player.playing) {
      return pause();
    }
    return play();
  }

  Future<void> setVolume(double volume) => _player.setVolume(volume.clamp(0.0, 1.0));

  Future<void> dispose() => _player.dispose();
}