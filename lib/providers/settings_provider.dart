import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings_store.dart';

/// User preferences, backed by a persisted `settings.json` (see
/// [SettingsStore]) so they survive restarts. Only these settings persist —
/// the transcript/audio session never does. Values are hydrated on startup via
/// [hydrateAndPersistSettings] and written back on every change.
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

/// Minimum silence (in seconds) between segments that triggers a new transcript
/// "part" tile. Range 0.5-5.0, default 2.0 (the original hardcoded threshold).
final partGapSecondsProvider = StateProvider<double>((ref) => 2.0);

/// Whether the transcript list is shown by default when a file is opened.
/// Defaults to false so playback-focused users aren't greeted with the list.
final showTranscriptByDefaultProvider = StateProvider<bool>((ref) => false);

/// The Whisper model in use. Persisted like the other user settings.
final selectedModelProvider = StateProvider<String>((ref) => 'base');

/// Selectable Whisper model sizes.
const availableModels = <String>[
  'tiny',
  'base',
  'small',
  'medium',
];

/// Whether the user has acknowledged the "I know what I'm doing" model-change
/// warning. Initialised asynchronously from the marker file.
final modelAcknowledgedProvider = FutureProvider<bool>((ref) {
  return ref.read(settingsStoreProvider).isModelAcknowledged();
});

/// Persistence keys kept in sync between the providers above and `settings.json`.
abstract final class _PrefKeys {
  static const model = 'model';
  static const wordLevel = 'wordLevel';
  static const skipBackSeconds = 'skipBackSeconds';
  static const skipForwardSeconds = 'skipForwardSeconds';
  static const partGapSeconds = 'partGapSeconds';
  static const showTranscriptByDefault = 'showTranscriptByDefault';
}

/// Snapshot of the persisted settings providers as a serializable map.
Map<String, dynamic> _snapshot(ProviderContainer container) => {
  _PrefKeys.model: container.read(selectedModelProvider),
  _PrefKeys.wordLevel: container.read(splitOnWordProvider),
  _PrefKeys.skipBackSeconds: container.read(skipBackSecondsProvider),
  _PrefKeys.skipForwardSeconds: container.read(skipForwardSecondsProvider),
  _PrefKeys.partGapSeconds: container.read(partGapSecondsProvider),
  _PrefKeys.showTranscriptByDefault:
      container.read(showTranscriptByDefaultProvider),
};

/// Loads persisted preferences into the container's setting providers, then
/// subscribes so any subsequent change writes the full snapshot back to disk.
/// Call once from startup before the app builds.
Future<void> hydrateAndPersistSettings(
  ProviderContainer container,
  SettingsStore store,
) async {
  final prefs = await store.loadPreferences();

  int asInt(String key, int fallback) {
    final v = prefs[key];
    return v is int ? v : fallback;
  }

  double asDouble(String key, double fallback) {
    final v = prefs[key];
    return v is num ? v.toDouble() : fallback;
  }

  bool asBool(String key, bool fallback) {
    final v = prefs[key];
    return v is bool ? v : fallback;
  }

  String asString(String key, String fallback) {
    final v = prefs[key];
    return v is String ? v : fallback;
  }

  container.read(selectedModelProvider.notifier).state =
      asString(_PrefKeys.model, 'base');
  container.read(splitOnWordProvider.notifier).state =
      asBool(_PrefKeys.wordLevel, false);
  container.read(skipBackSecondsProvider.notifier).state =
      asInt(_PrefKeys.skipBackSeconds, 10);
  container.read(skipForwardSecondsProvider.notifier).state =
      asInt(_PrefKeys.skipForwardSeconds, 30);
  container.read(partGapSecondsProvider.notifier).state =
      asDouble(_PrefKeys.partGapSeconds, 2.0);
  container.read(showTranscriptByDefaultProvider.notifier).state =
      asBool(_PrefKeys.showTranscriptByDefault, false);

  void persistOnChange<T>(StateProvider<T> provider) {
    container.listen(provider, (prev, next) {
      // Only write on actual changes, not on the very first emission (which
      // equals the value we just hydrated).
      if (prev != next) {
        unawaited(store.savePreferences(_snapshot(container)));
      }
    }, fireImmediately: false);
  }

  persistOnChange(selectedModelProvider);
  persistOnChange(splitOnWordProvider);
  persistOnChange(skipBackSecondsProvider);
  persistOnChange(skipForwardSecondsProvider);
  persistOnChange(partGapSecondsProvider);
  persistOnChange(showTranscriptByDefaultProvider);
}
