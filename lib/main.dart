import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'providers/settings_provider.dart';
import 'services/file_open_service.dart';
import 'services/window_service.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // A shared container so file-open events (from launch args or the platform)
  // can reach the app's providers outside the widget tree.
  final container = ProviderContainer();

  // Load persisted user settings (model, skip durations, part gap, etc.) so the
  // app opens with the user's saved preferences, and start listening so any
  // change is written back. The transcript/audio session itself is never
  // persisted — only these settings are.
  final settingsStore = container.read(settingsStoreProvider);
  await hydrateAndPersistSettings(container, settingsStore);

  final fileOpen = FileOpenService(container);

  // Apply the desktop window size policy (initial size + min/max) before the
  // app UI builds. No-op on unsupported platforms.
  unawaited(WindowService.instance.initialize());

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