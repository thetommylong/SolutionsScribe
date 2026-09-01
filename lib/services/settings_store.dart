import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persists a tiny set of app flags (not user preferences — those stay in
/// memory for the session). Backed by the presence of a 0-byte marker file in
/// the app support directory, so we don't need a config parser or schema.
class SettingsStore {
  /// Marker file name for the one-time "I know what I'm doing" model-change
  /// acknowledgement. Its *existence* (any bytes, we always write 0) means the
  /// user has already confirmed; this survives app restarts so they're only
  /// ever asked once.
  static const String modelAckFileName = 'whisper-model-ack';

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
}
