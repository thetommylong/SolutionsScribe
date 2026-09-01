import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'components/app_shortcuts.dart';
import 'components/osd_overlay.dart';
import 'providers/app_state_provider.dart';
import 'theme/app_theme.dart';
import 'views/transcript_view.dart';
import 'views/upload_view.dart';

class SolutionsScribeApp extends StatelessWidget {
  const SolutionsScribeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SolutionsScribe',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.mocha,
      home: const AppShell(),
    );
  }
}

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stage = ref.watch(appStateProvider.select((s) => s.stage));

    Widget view;
    switch (stage) {
      case AppStage.ready:
        view = const TranscriptView();
      case AppStage.idle:
      case AppStage.processing:
      case AppStage.error:
        view = const UploadView();
    }

    return AppShortcuts(
      child: Stack(
        children: [
          view,
          const Positioned.fill(child: OsdOverlay()),
        ],
      ),
    );
  }
}
