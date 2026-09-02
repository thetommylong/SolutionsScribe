import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/file_open_service.dart';
import 'services/linux_association_service.dart';
import 'services/window_service.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();

  // A shared container so file-open events (from launch args or the platform)
  // can reach the app's providers outside the widget tree.
  final container = ProviderContainer();
  final fileOpen = FileOpenService(container);

  // Apply the desktop window size policy (initial size + min/max) before the
  // app UI builds. No-op on unsupported platforms.
  unawaited(WindowService.instance.initialize());

  // Install/refresh the Linux file association (no-op elsewhere). Best-effort.
  unawaited(LinuxAssociationService.register());

  runApp(UncontrolledProviderScope(
    container: container,
    child: const SolutionsScribeApp(),
  ));

  // "Open with" / drag-onto-icon: an audio file passed as the first launch
  // argument (Linux/Windows pass these straight through; macOS arrives later
  // via the FileOpenService method channel). Open it once the UI is up.
  if (args.isNotEmpty) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fileOpen.open(args.first);
    });
  }
}