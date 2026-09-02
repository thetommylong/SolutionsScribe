import 'dart:io';

import 'package:flutter/foundation.dart';

/// Makes SolutionsScribe the default handler for the audio files it supports
/// on Linux by installing a user-level (no root) freedesktop [.desktop] entry
/// and registering it as the default application for the matching MIME types.
///
/// This is what lets a double-click on an .mp3 in the file manager open the
/// file in SolutionsScribe. The `Exec` points at the currently-running
/// executable, so re-registering after a rebuild keeps it correct. All writes
/// are best-effort and never fail app startup.
class LinuxAssociationService {
  static const String _desktopId = 'solutionscribe.desktop';
  static const List<String> _mimeTypes = [
    'audio/mpeg',
    'audio/x-wav',
    'audio/wav',
    'audio/mp4',
    'audio/x-m4a',
  ];

  /// Registers the file association. Safe to call repeatedly (idempotent).
  static Future<void> register() async {
    if (!Platform.isLinux) return;
    try {
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return;
      await _ensureDesktopFile(home);
      await _ensureDefaultApplications(home);
    } catch (e) {
      debugPrint('[SolutionsScribe] Linux file association install failed: $e');
    }
  }

  static Future<void> _ensureDesktopFile(String home) async {
    final appsDir = Directory('$home/.local/share/applications');
    await appsDir.create(recursive: true);
    final desktopPath = '${appsDir.path}/$_desktopId';

    final existing = File(desktopPath).existsSync()
        ? File(desktopPath).readAsStringSync()
        : '';
    // Re-write only if the entry is missing or points at a stale executable.
    if (existing.contains('[Desktop Entry]') &&
        existing.contains('Exec=$_exeQuoted')) {
      return;
    }

    final content = [
      '[Desktop Entry]',
      'Type=Application',
      'Name=SolutionsScribe',
      'Comment=Transcribe audio recordings',
      'Exec=$_exeQuoted %U',
      'Terminal=false',
      'MimeType=${_mimeTypes.join(';')};',
      'Categories=AudioVideo;Audio;Utility;',
      'NoDisplay=false',
      'StartupNotify=true',
    ].join('\n');

    final f = File(desktopPath);
    await f.writeAsString(content, flush: true);
    debugPrint('[SolutionsScribe] installed $desktopPath');
  }

  static String get _exeQuoted => '"${Platform.resolvedExecutable}"';

  static Future<void> _ensureDefaultApplications(String home) async {
    final configFile = File('$home/.config/mimeapps.list');
    await configFile.create(recursive: true);
    var text = configFile.existsSync()
        ? configFile.readAsStringSync()
        : '[Default Applications]\n';

    for (final mime in _mimeTypes) {
      final key = '$mime=';
      final values = text
          .split('\n')
          .where((l) => l.startsWith(key))
          .expand((l) => l.substring(key.length).split(';'))
          .where((d) => d.isNotEmpty)
          .toSet();
      if (values.contains(_desktopId)) continue;
      // Put our handler first, preserving any existing fallbacks.
      final line = '$key$_desktopId;${values.join(';')}';
      text = text
          .split('\n')
          .where((l) => !l.startsWith(key))
          .join('\n');
      text = '$text\n$line';
    }

    await configFile.writeAsString(text, flush: true);
    debugPrint('[SolutionsScribe] registered default applications in '
        '$configFile');
  }
}