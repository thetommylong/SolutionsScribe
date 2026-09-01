import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/volume_provider.dart';
import '../theme/app_theme.dart';

/// Transient on-screen display: a top-center pill showing a message (e.g.
/// "Volume: 70%"), auto-hidden by [osdProvider]. Rendered above the view and
/// ignores pointer events so it never blocks the UI.
class OsdOverlay extends ConsumerWidget {
  const OsdOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(osdProvider);
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: message == null
              ? const SizedBox.shrink()
              : Semantics(
                  liveRegion: true,
                  label: message,
                  child: Container(
                    key: ValueKey(message),
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: mochaSurface0,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: mochaText,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}