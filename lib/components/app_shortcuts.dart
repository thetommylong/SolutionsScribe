import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_state_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/volume_provider.dart';
import 'settings_dialog.dart';

/// App-global keyboard shortcuts for playback and navigation.
///
/// Wraps its child in a [CallbackShortcuts] whose internal [Focus] owns the
/// key handling. Key events only reach it while keyboard focus is somewhere
/// within its subtree, so the autofocusing [Focus] must be *inside* the
/// shortcuts (an autofocus node above them would swallow the events before
/// the bindings run). Typing in a text field (settings duration fields) is not
/// hijacked because those run their own handlers / are guarded explicitly.
class AppShortcuts extends ConsumerWidget {
  final Widget child;

  const AppShortcuts({super.key, required this.child});

  bool _hasEditableFocus(BuildContext context) {
    final f = FocusManager.instance.primaryFocus;
    if (f == null) return false;
    return f.context?.widget is EditableText;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () {
          if (_hasEditableFocus(context)) return;
          _togglePlayPause(context, ref);
        },
        // Shift+left/right: snap to previous / next transcript part.
        const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): () {
          if (_hasEditableFocus(context)) return;
          _snapToPart(context, ref, forward: false);
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): () {
          if (_hasEditableFocus(context)) return;
          _snapToPart(context, ref, forward: true);
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          if (_hasEditableFocus(context)) return;
          _skip(context, ref, forward: false, shift: false);
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          if (_hasEditableFocus(context)) return;
          _skip(context, ref, forward: true, shift: false);
        },
        // Up/down: adjust volume. Always volume (never list scroll), to keep
        // the shortcut predictable — see plan/decision.
        const SingleActivator(LogicalKeyboardKey.arrowUp): () {
          if (_hasEditableFocus(context)) return;
          _adjustVolume(context, ref, delta: 0.1);
        },
        const SingleActivator(LogicalKeyboardKey.arrowDown): () {
          if (_hasEditableFocus(context)) return;
          _adjustVolume(context, ref, delta: -0.1);
        },
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () {
          _toggleTranscript(ref);
        },
        const SingleActivator(LogicalKeyboardKey.keyH, meta: true): () {
          _toggleTranscript(ref);
        },
        const SingleActivator(LogicalKeyboardKey.comma, control: true): () {
          _openSettings(context);
        },
        const SingleActivator(LogicalKeyboardKey.comma, meta: true): () {
          _openSettings(context);
        },
      },
      child: Focus(autofocus: true, child: child),
    );
  }

  static void _togglePlayPause(BuildContext context, WidgetRef ref) {
    final stage = ref.read(appStateProvider).stage;
    if (stage != AppStage.ready) return;
    ref.read(audioPlayerServiceProvider).togglePlayPause();
  }

  static void _toggleTranscript(WidgetRef ref) {
    final notifier = ref.read(transcriptVisibleProvider.notifier);
    notifier.state = !ref.read(transcriptVisibleProvider);
  }

  static void _adjustVolume(
    BuildContext context,
    WidgetRef ref, {
    required double delta,
  }) {
    final stage = ref.read(appStateProvider).stage;
    if (stage != AppStage.ready) return;
    ref.read(volumeProvider.notifier).adjust(delta);
  }

  static void _skip(
    BuildContext context,
    WidgetRef ref, {
    required bool forward,
    required bool shift,
  }) {
    final seconds = ref.read(
      forward ? skipForwardSecondsProvider : skipBackSecondsProvider,
    );
    final audio = ref.read(audioPlayerServiceProvider);
    if (forward) {
      audio.skipForward(Duration(seconds: seconds));
    } else {
      audio.skipBackward(Duration(seconds: seconds));
    }
  }

  static void _snapToPart(
    BuildContext context,
    WidgetRef ref, {
    required bool forward,
  }) {
    final parts = ref.read(appStateProvider).parts;
    if (parts.isEmpty) return;

    final starts = <Duration>[
      for (final p in parts)
        if (p.segments.isNotEmpty) p.segments.first.fromTs,
    ];
    if (starts.isEmpty) return;

    final position = ref.read(audioPlayerServiceProvider).position;
    final audio = ref.read(audioPlayerServiceProvider);

    if (forward) {
      // Find the first part start strictly after the current position.
      final target = starts.firstWhere(
        (t) => t > position,
        orElse: () => starts.last,
      );
      audio.seek(target);
    } else {
      // Find the last part start strictly before (or at) the current position,
      // preferring the previous one when already inside a part.
      Duration? target;
      for (final t in starts) {
        if (t < position - const Duration(milliseconds: 150)) {
          target = t;
        }
      }
      audio.seek(target ?? starts.first);
    }
  }

  static void _openSettings(BuildContext context) {
    showDialog<void>(context: context, builder: (_) => const SettingsDialog());
  }
}
