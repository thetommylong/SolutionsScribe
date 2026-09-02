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
    final isTranscribing =
        ref.watch(appStateProvider.select((s) => s.isTranscribing));
    final transcribeError =
        ref.watch(appStateProvider.select((s) => s.transcribeError));

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
          if (isTranscribing)
            const _TranscribingBanner(),
          if (transcribeError != null)
            _StatusBanner(
              message: 'Transcription failed: $transcribeError',
              color: mochaRed,
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

/// Live progress banner shown while transcription runs in the background. The
/// phase/percent come from the transcription service's callbacks and update in
/// place. Progress is conveyed by a thin horizontal bar that fills in per
/// percent; when a phase reports no granular progress (e.g. whisper inference,
/// which only emits coarse callbacks) the bar animates as an indeterminate
/// loop so it never sits frozen. The banner is announced to screen readers via
/// a live region.
class _TranscribingBanner extends ConsumerWidget {
  const _TranscribingBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(appStateProvider.select((s) => s.phase));
    final percent = ref.watch(appStateProvider.select((s) => s.percent));

    final label = phase ?? 'Transcribing…';
    // Determinately filled whenever we have a real, in-progress fraction;
    // indeterminate (animated) otherwise so the bar keeps moving even when a
    // phase reports no granular progress.
    final filled = percent > 0 && percent < 100 ? percent / 100 : null;
    final percentText = percent > 0
        ? Text(
            '$percent%',
            style: const TextStyle(
              color: mochaText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          )
        : null;

    return Semantics(
      liveRegion: true,
      label: label,
      child: Container(
        width: double.infinity,
        color: mochaMauve.withValues(alpha: 0.10),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: mochaText,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (percentText != null) ...[
                  const SizedBox(width: 8),
                  percentText,
                ],
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(6),
              ),
              child: LinearProgressIndicator(
                minHeight: 4,
                value: filled,
                color: mochaMauve,
                backgroundColor: mochaMauve.withValues(alpha: 0.20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String message;
  final Color color;

  const _StatusBanner({
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
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
