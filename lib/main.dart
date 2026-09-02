import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/window_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Apply the desktop window size policy (initial size + min/max) before the
  // app UI builds. No-op on unsupported platforms.
  unawaited(WindowService.instance.initialize());
  runApp(const ProviderScope(child: SolutionsScribeApp()));
}
