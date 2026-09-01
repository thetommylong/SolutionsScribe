import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/settings_dialog.dart';
import '../components/upload_dropzone.dart';
import '../theme/app_theme.dart';

class UploadView extends ConsumerWidget {
  const UploadView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: mochaBase,
      body: Stack(
        children: [
          const Center(child: UploadDropzone()),
          // Settings cog, top-right corner.
          Positioned(
            top: 12,
            right: 12,
            child: _SettingsButton(
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => const SettingsDialog(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsButton extends StatefulWidget {
  final VoidCallback onTap;

  const _SettingsButton({required this.onTap});

  @override
  State<_SettingsButton> createState() => _SettingsButtonState();
}

class _SettingsButtonState extends State<_SettingsButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _hovered
                ? mochaMauve.withValues(alpha: 0.12)
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.settings_rounded,
            size: 22,
            color: _hovered ? mochaMauve : mochaSubtext0,
          ),
        ),
      ),
    );
  }
}

