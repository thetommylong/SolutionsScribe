import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_state_provider.dart';
import '../utils/audio_file_utils.dart';

/// Bridges "open this file with SolutionsScribe" requests from the operating
/// system into the app's transcription pipeline.
///
/// Three entry paths feed in here:
///  - launch arguments (drag a file onto the app icon, or `open file.mp3`),
///  - macOS `application:openFile(s:)` callbacks (raised when a file is opened
///    on an already-running app via the Dock / Finder),
///  - OS file associations (double-click an audio file) which surface through
///    the same launch/open events on each platform.
///
/// In-window drag-and-drop is handled separately by the dropzone.
class FileOpenService {
  static const MethodChannel _channel = MethodChannel('solutionscribe/file_open');

  final ProviderContainer _container;

  FileOpenService(this._container) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      _channel.setMethodCallHandler(_onMethodCall);
    }
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    final path = call.arguments as String?;
    if (call.method == 'openFile' && path != null) {
      open(path);
    }
  }

  /// Validates [filePath] and routes it into transcription, replacing whatever
  /// is currently shown. Unsupported files are ignored with a log line.
  void open(String filePath) {
    final path = _normalizePath(filePath);
    if (!isSupportedAudioFile(path)) {
      debugPrint('[SolutionsScribe] ignoring unsupported file: $filePath');
      return;
    }
    final name = fileNameFromPath(path);
    debugPrint('[SolutionsScribe] opening external file: $name');
    _container.read(appStateProvider.notifier).processFile(path, name);
  }

  /// Converts a `file://` URI (as passed by desktop environments via the
  /// `.desktop` `%U` field code) into a plain filesystem path, and passes
  /// plain paths through unchanged.
  static String _normalizePath(String raw) {
    if (raw.startsWith('file://')) {
      // file:///home/u/x.mp3 -> /home/u/x.mp3 (and file://localhost/...).
      return Uri.decodeComponent(raw.substring(7).replaceFirst('localhost', ''));
    }
    return raw;
  }
}