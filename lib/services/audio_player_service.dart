import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:media_kit/media_kit.dart' as mk;

/// Audio playback service.
///
/// Abstractions over two backends:
///  - `media_kit` on Linux. just_audio's Linux bridge (`just_audio_media_kit`)
///    runs mpv with `cache-on-disk: yes` hardcoded, which can fail and break
///    playback on some Linux setups ("Failed to create file cache"). Since
///    SolutionsScribe only plays local files, we drive media_kit's Player
///    directly with disk caching disabled.
///  - `just_audio` on other platforms (macOS / iOS / Android / Windows),
///    which use their native plugins.
class AudioPlayerService {
  final mk.Player? _mediaKit;
  final AudioPlayer? _justAudio;

  AudioPlayerService()
      : _mediaKit = defaultTargetPlatform == TargetPlatform.linux
            ? AudioPlayerService._buildMediaKitPlayer()
            : null,
        _justAudio = defaultTargetPlatform == TargetPlatform.linux
            ? null
            : AudioPlayer();

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

  bool get isLinux => _mediaKit != null;

  StreamingBackend get _player {
    final mp = _mediaKit;
    return mp != null ? MediaKitStreaming(mp) : JustAudioStreaming(_justAudio!);
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
    _justAudio?.dispose();
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

class JustAudioStreaming implements StreamingBackend {
  final AudioPlayer _player;

  JustAudioStreaming(this._player);

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Duration get position => _player.position;

  @override
  Duration get duration => _player.duration ?? Duration.zero;

  @override
  bool get playing => _player.playing;

  @override
  Future<void> loadFile(String path) => _player.setFilePath(path);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);
}
