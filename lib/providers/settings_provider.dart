import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings_store.dart';

/// Session-scoped settings. These are intentionally NOT persisted: the app's
/// user preferences live only in memory and reset on restart (the only thing
/// persisted on disk is the model-change acknowledgement marker, see
/// [SettingsStore]).
///
/// All of these are safe to read with `ref.read(...)` or `ref.watch(...)`
/// anywhere in the app.
final settingsStoreProvider = Provider<SettingsStore>((ref) {
  return SettingsStore();
});

/// Whether whisper emits word-level timestamps instead of segment-level.
final splitOnWordProvider = StateProvider<bool>((ref) => false);
/// Playback skip-back duration, in seconds.
final skipBackSecondsProvider = StateProvider<int>((ref) => 10);

/// Playback skip-forward duration, in seconds.
final skipForwardSecondsProvider = StateProvider<int>((ref) => 30);

/// Whether the user has acknowledged the "I know what I'm doing" model-change
/// warning. Initialised asynchronously from the marker file.
final modelAcknowledgedProvider = FutureProvider<bool>((ref) {
  return ref.read(settingsStoreProvider).isModelAcknowledged();
});
