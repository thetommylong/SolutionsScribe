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
/// phase/percent come from the transcription service's callbacks and update
/// in place; progress is conveyed by the determinate ring + percent label
/// (never baked into the phase string). The banner is announced to screen
/// readers via a live region.
class _TranscribingBanner extends ConsumerWidget {
  const _TranscribingBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(appStateProvider.select((s) => s.phase));
    final percent = ref.watch(appStateProvider.select((s) => s.percent));

    final label = phase ?? 'Transcribing…';
    // Same determinate/indeterminate idiom as the upload dropzone's progress
    // ring: a value is a 0-1 progress fraction when we have one.
    final ring = SizedBox(
      width: 12,
      height: 12,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        value: percent > 0 ? percent / 100 : null,
        color: mochaMauve,
      ),
    );
    final percentText = percent > 0
        ? Text(
            '$percent%',
            style: const TextStyle(
              color: mochaMauve,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          )
        : null;

    return Semantics(
      liveRegion: true,
      label: label,
      child: _StatusBanner(
        message: label,
        color: mochaMauve,
        leading: ring,
        trailing: percentText,
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String message;
  final Color color;
  final Widget? leading;
  final Widget? trailing;

  const _StatusBanner({
    required this.message,
    required this.color,
    this.leading,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 8),
          ],
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
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
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
