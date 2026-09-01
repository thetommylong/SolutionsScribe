import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_state_provider.dart';

/// Playback volume, normalized to [0.0, 1.0]. Source of truth for both the
/// slider and the ↑/↓ key shortcuts. Session-scoped (not persisted), matching
/// the app's in-memory settings convention.
final volumeProvider = StateNotifierProvider<VolumeNotifier, double>((ref) {
  return VolumeNotifier(ref);
});

/// Transient on-screen display text (e.g. "Volume: 70%"), auto-cleared after a
/// short delay. Shown on keyboard volume changes and mute toggles only.
final osdProvider = StateNotifierProvider<OsdNotifier, String?>((ref) {
  return OsdNotifier();
});

class VolumeNotifier extends StateNotifier<double> {
  VolumeNotifier(this._ref) : super(1.0);

  final Ref _ref;

  double _lastNonZero = 1.0;

  double _clamp(double volume) => volume.clamp(0.0, 1.0).toDouble();

  /// Applies a new volume (slider drags). Does not raise the on-screen
  /// display — the slider already gives live feedback.
  void set(double volume) {
    final v = _clamp(volume);
    if (v == state) return;
    state = v;
    if (v != 0.0) _lastNonZero = v;
    _ref.read(audioPlayerServiceProvider).setVolume(v);
  }

  /// Steps the volume by [delta] (typically ±0.1) and raises the on-screen
  /// display. Used by the ↑/↓ shortcuts.
  void adjust(double delta) {
    final v = _clamp(state + delta);
    set(v);
    _showOsd(v);
  }

  /// Toggles between muted and the last non-zero level.
  void toggleMute() {
    if (state == 0.0) {
      set(_lastNonZero);
      _showOsd(_lastNonZero);
    } else {
      set(0.0);
      _showOsd(0.0);
    }
  }

  void _showOsd(double volume) {
    _ref.read(osdProvider.notifier).show(
      volume == 0.0
          ? 'Muted'
          : 'Volume: ${(volume * 100).round()}%',
    );
  }
}

class OsdNotifier extends StateNotifier<String?> {
  OsdNotifier() : super(null);

  Timer? _hideTimer;

  void show(String message) {
    _hideTimer?.cancel();
    state = message;
    _hideTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) state = null;
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }
}