import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persists two distinct kinds of state:
///
/// 1. **User preferences** — a `settings.json` map of the session settings
///    (model, word-level, skip durations, part gap, show-transcript-default).
///    These are loaded on startup and written back whenever any of them
///    changes, so they survive restarts. Only these *settings* persist: the
///    transcript/audio session itself never does.
/// 2. **A one-time marker file** for the model-change acknowledgement, backed
///    by the *existence* of a 0-byte file (we don't need a parser for it).
class SettingsStore {
  /// Marker file name for the one-time "I know what I'm doing" model-change
  /// acknowledgement. Its *existence* (any bytes, we always write 0) means the
  /// user has already confirmed; this survives app restarts so they're only
  /// ever asked once.
  static const String modelAckFileName = 'whisper-model-ack';

  /// File name of the persisted user-preferences map.
  static const String settingsFileName = 'settings.json';

  /// Optional override of the support directory, for tests. When null the real
  /// `getApplicationSupportDirectory()` is used.
  final String? _supportDirOverride;

  SettingsStore({String? supportDirOverride})
      : _supportDirOverride = supportDirOverride;
  Future<String> _supportDir() async =>
      _supportDirOverride ?? (await getApplicationSupportDirectory()).path;

  Future<File> _markerFile(String name) async {
    final support = await _supportDir();
    return File('$support${Platform.pathSeparator}$name');
  }

  /// True if the user has already acknowledged the model-change warning.
  Future<bool> isModelAcknowledged() async {
    final file = await _markerFile(modelAckFileName);
    return file.existsSync();
  }

  /// Persist the acknowledgement as a 0-byte marker file.
  Future<void> markModelAcknowledged() async {
    final file = await _markerFile(modelAckFileName);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(const [], flush: true);
  }

  Future<File> _settingsFile() async {
    final support = await _supportDir();
    return File('$support${Platform.pathSeparator}$settingsFileName');
  }

  /// Reads the persisted preferences map. Returns an empty map when the file
  /// is absent, unreadable, or corrupt — callers fall back to their in-code
  /// defaults for whatever keys are missing.
  Future<Map<String, dynamic>> loadPreferences() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) return const {};
      final contents = await file.readAsString();
      final decoded = jsonDecode(contents);
      // jsonDecode can yield a List or a primitive; only accept a map.
      if (decoded is! Map<String, dynamic>) return const {};
      return decoded;
    } catch (_) {
      return const {};
    }
  }

  /// Writes the preferences map as JSON. A missing/corrupt file is simply
  /// overwritten. Failures are swallowed: losing persistence is not worth
  /// failing a settings interaction the user can still use in-memory.
  Future<void> savePreferences(Map<String, dynamic> prefs) async {
    try {
      final file = await _settingsFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(prefs),
        flush: true,
      );
    } catch (_) {
      // Intentionally silent.
    }
  }
}
