import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_state_provider.dart';

/// Playback volume, normalized to [0.0, 1.0]. Source of truth for both the
/// slider and the ↑/↓ key shortcuts. Session-scoped (not persisted), matching
/// the app's in-memory settings convention.
final volumeProvider = StateNotifierProvider<VolumeNotifier, double>((ref) {
  return VolumeNotifier(ref);
});

class VolumeNotifier extends StateNotifier<double> {
  VolumeNotifier(this._ref) : super(1.0);

  final Ref _ref;

  double _lastNonZero = 1.0;

  double _clamp(double volume) => volume.clamp(0.0, 1.0).toDouble();

  /// Applies a new volume (slider drags or ↑/↓ shortcuts).
  void set(double volume) {
    final v = _clamp(volume);
    if (v == state) return;
    state = v;
    if (v != 0.0) _lastNonZero = v;
    _ref.read(audioPlayerServiceProvider).setVolume(v);
  }

  /// Steps the volume by [delta] (typically ±0.1, from the ↑/↓ shortcuts).
  void adjust(double delta) => set(state + delta);

  /// Toggles between muted and the last non-zero level.
  void toggleMute() {
    if (state == 0.0) {
      set(_lastNonZero);
    } else {
      set(0.0);
    }
  }
}