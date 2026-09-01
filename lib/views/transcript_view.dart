import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/playback_bar.dart';
import '../components/transcript_list.dart';
import '../providers/app_state_provider.dart';
import '../theme/app_theme.dart';

class TranscriptView extends ConsumerWidget {
  const TranscriptView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transcriptVisible = ref.watch(transcriptVisibleProvider);

    return Scaffold(
      backgroundColor: mochaBase,
      body: Column(
        children: [
          _Header(
            onBack: () {
              // Stop playback before leaving the player so audio doesn't
              // keep playing after the transcript screen closes.
              ref.read(audioPlayerServiceProvider).pause();
              ref.read(appStateProvider.notifier).reset();
            },
          ),
          if (transcriptVisible)
            const Expanded(child: TranscriptList())
          else
            const Expanded(child: SizedBox.shrink()),
          const PlaybackBar(),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  final VoidCallback onBack;

  const _Header({required this.onBack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(appStateProvider.select((s) => s.track));
    final transcriptVisible = ref.watch(transcriptVisibleProvider);

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: mochaMantle,
        border: Border(bottom: BorderSide(color: mochaSurface0, width: 1)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(8),
            child: Tooltip(
              message: 'Back to upload',
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Semantics(
                  label: 'Back',
                  button: true,
                  excludeSemantics: true,
                  child:
                      Icon(Icons.arrow_back, size: 20, color: mochaSubtext0),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              track?.title ?? 'Transcript',
              style: const TextStyle(
                color: mochaText,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Tooltip(
            message: transcriptVisible ? 'Hide transcript' : 'Show transcript',
            child: InkWell(
              onTap: () => ref.read(transcriptVisibleProvider.notifier).state =
                  !transcriptVisible,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Semantics(
                  label: transcriptVisible
                      ? 'Hide transcript'
                      : 'Show transcript',
                  button: true,
                  excludeSemantics: true,
                  child: Icon(
                    transcriptVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: mochaSubtext0,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
