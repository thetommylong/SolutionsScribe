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
          const Expanded(child: TranscriptList()),
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
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.arrow_back, size: 20, color: mochaSubtext0),
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
        ],
      ),
    );
  }
}
