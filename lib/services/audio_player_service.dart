import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;

import '../audio/solutions_audio_handler.dart';

/// Audio playback service.
///
/// Abstractions over two backends:
///  - `media_kit` on Linux. just_audio's Linux bridge (`just_audio_media_kit`)
///    runs mpv with `cache-on-disk: yes` hardcoded, which can fail and break
///    playback on some Linux setups ("Failed to create file cache"). Since
///    SolutionsScribe only plays local files, we drive media_kit's Player
///    directly with disk caching disabled.
///  - `just_audio` on other platforms (macOS / iOS / Android / Windows), which
///    use their native plugins. On those platforms playback is also published
///    to the OS media session via [audio_service] so now-playing metadata and
///    transport controls show in macOS Now Playing / Control Center and Windows
///    System Media Transport Controls.
class AudioPlayerService {
  final mk.Player? _mediaKit;
  final SolutionsAudioHandler? _handler;

  AudioPlayerService()
      : _mediaKit = defaultTargetPlatform == TargetPlatform.linux
            ? AudioPlayerService._buildMediaKitPlayer()
            : null,
        _handler = defaultTargetPlatform == TargetPlatform.linux
            ? null
            : _buildOsHandler();

  static mk.Player _buildMediaKitPlayer() {
    mk.MediaKit.ensureInitialized();
    return mk.Player(
      configuration: const mk.PlayerConfiguration(
        title: 'SolutionsScribe',
        logLevel: mk.MPVLogLevel.error,
        bufferSize: 8 * 1024 * 1024,
      ),
    );
  }

  /// On non-Linux platforms playback runs through a [SolutionsAudioHandler],
  /// which owns the `just_audio` player and publishes to the OS media session.
  static SolutionsAudioHandler _buildOsHandler() {
    final handler = SolutionsAudioHandler();
    // Bind audio_service to the handler's player / media session. We must
    // tolerate this being called on any non-Linux desktop target.
    try {
      AudioService.init(builder: () => handler);
    } catch (e) {
      debugPrint('[SolutionsScribe] audio_service init failed: $e');
    }
    return handler;
  }

  bool get isLinux => _mediaKit != null;

  /// The OS-published handler, or null on Linux (media_kit has no audio_service
  /// integration here). Used by the UI/provider layer to update now-playing
  /// metadata once a track is loaded.
  SolutionsAudioHandler? get osHandler => _handler;

  StreamingBackend get _player {
    final mp = _mediaKit;
    if (mp != null) return MediaKitStreaming(mp);
    return HandlerStreaming(_handler!);
  }

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;

  Duration get position => _player.position;
  Duration get duration => _player.duration;
  bool get playing => _player.playing;

  Future<void> loadFile(String path) => _player.loadFile(path);
  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> togglePlayPause() => _player.togglePlayPause();

  /// Sets playback volume, normalized to [0.0, 1.0] regardless of backend.
  /// (media_kit uses 0-100, just_audio uses 0.0-1.0; the abstraction hides
  /// that difference.)
  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0.0, 1.0));

  Future<void> seek(Duration position) {
    final dur = duration;
    final clamped = position.isNegative
        ? Duration.zero
        : (dur > Duration.zero && position > dur ? dur : position);
    return _player.seek(clamped);
  }

  Future<void> skipForward([
    Duration duration = const Duration(seconds: 30),
  ]) =>
      seek(position + duration);

  Future<void> skipBackward([
    Duration duration = const Duration(seconds: 10),
  ]) =>
      seek(position - duration);

  void dispose() {
    _mediaKit?.dispose();
    _handler?.dispose();
  }
}

/// Common playback surface so call sites are platform-agnostic.
abstract class StreamingBackend {
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<bool> get playingStream;

  Duration get position;
  Duration get duration;
  bool get playing;

  Future<void> loadFile(String path);
  Future<void> play();
  Future<void> pause();
  Future<void> togglePlayPause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
}

class MediaKitStreaming implements StreamingBackend {
  final mk.Player _player;

  MediaKitStreaming(this._player);

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration?> get durationStream => _player.stream.duration;

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Duration get position => _player.state.position;

  @override
  Duration get duration => _player.state.duration;

  @override
  bool get playing => _player.state.playing;

  @override
  Future<void> loadFile(String path) =>
      _player.open(mk.Media('file://$path'), play: false);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> togglePlayPause() => _player.playOrPause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume * 100);
}

/// Non-Linux backend: delegates every call to the [SolutionsAudioHandler],
/// which owns the underlying `just_audio` player and keeps the OS media
/// session in sync.
class HandlerStreaming implements StreamingBackend {
  final SolutionsAudioHandler _handler;

  HandlerStreaming(this._handler);

  @override
  Stream<Duration> get positionStream => _handler.positionStream;

  @override
  Stream<Duration?> get durationStream => _handler.durationStream;

  @override
  Stream<bool> get playingStream => _handler.playingStream;

  @override
  Duration get position => _handler.position;

  @override
  Duration get duration => _handler.duration;

  @override
  bool get playing => _handler.playing;

  @override
  Future<void> loadFile(String path) =>
      _handler.loadFile(path, title: _titleFromPath(path));

  @override
  Future<void> play() => _handler.play();

  @override
  Future<void> pause() => _handler.pause();

  @override
  Future<void> togglePlayPause() => _handler.playPause();

  @override
  Future<void> seek(Duration position) => _handler.seek(position);

  @override
  Future<void> setVolume(double volume) => _handler.setVolume(volume);

  String _titleFromPath(String path) {
    final base = path.split(Platform.pathSeparator).last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }
}