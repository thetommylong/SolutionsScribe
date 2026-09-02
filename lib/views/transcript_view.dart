import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/playback_bar.dart';
import '../components/transcript_list.dart';
import '../providers/app_state_provider.dart';
import '../services/window_service.dart';
import '../theme/app_theme.dart';

class TranscriptView extends ConsumerWidget {
  const TranscriptView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transcriptVisible = ref.watch(transcriptVisibleProvider);
    final isTranscribing =
        ref.watch(appStateProvider.select((s) => s.isTranscribing));
    final hasParts =
        ref.watch(appStateProvider.select((s) => s.parts.isNotEmpty));
    final transcribeError =
        ref.watch(appStateProvider.select((s) => s.transcribeError));

    // Resize the window to fit when the transcript is shown/hidden, so hiding
    // it doesn't leave a blank transcript region.
    ref.listen(transcriptVisibleProvider, (prev, next) {
      unawaited(WindowService.instance.setTranscriptVisible(next));
    });

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
          if (transcribeError != null)
            _StatusBanner(
              message: 'Transcription failed: $transcribeError',
              color: mochaRed,
            ),
          if (transcriptVisible) ...[
            if (isTranscribing && !hasParts)
              const Expanded(child: _TranscribingPlaceholder())
            else
              const Expanded(child: TranscriptList()),
          ] else
            const Expanded(child: SizedBox.shrink()),
          const PlaybackBar(),
        ],
      ),
    );
  }
}

/// Full-area state shown in the transcript region while the whole file is
/// being transcribed and there is no transcript yet. Makes the "working in
/// the background" pass legible instead of leaving a blank void. Progress and
/// a live time-remaining estimate are derived from the percent callback and
/// the pass's start time; a 1s timer ticks the estimate without touching
/// global state on every frame.
class _TranscribingPlaceholder extends ConsumerStatefulWidget {
  const _TranscribingPlaceholder();

  @override
  ConsumerState<_TranscribingPlaceholder> createState() =>
      _TranscribingPlaceholderState();
}

class _TranscribingPlaceholderState
    extends ConsumerState<_TranscribingPlaceholder> {
  Timer? _ticker;

  /// Rolling (elapsedSeconds, percent) samples used to smooth the rate so the
  /// ETA doesn't jump around when whisper phases advance lumpily. Kept small
  /// (a ~15s window) for a responsive yet stable estimate.
  final _Samples _samples = _Samples(maxLength: 15);

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final s = ref.read(appStateProvider);
      _samples.record(_secondsSince(s.startedAt, DateTime.now()), s.percent);
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  double _secondsSince(DateTime? start, DateTime now) =>
      start == null ? 0 : now.difference(start).inMilliseconds / 1000.0;

  @override
  Widget build(BuildContext context) {
    final phase = ref.watch(appStateProvider.select((s) => s.phase));
    final percent = ref.watch(appStateProvider.select((s) => s.percent));
    final startedAt = ref.watch(appStateProvider.select((s) => s.startedAt));

    // Keep the sample window seeded with the very first datum so an estimate
    // is reachable as soon as progress begins, even before the first tick.
    if (_samples.isEmpty && startedAt != null) {
      _samples.record(_secondsSince(startedAt, DateTime.now()), percent);
    }

    final label = phase ?? 'Transcribing…';
    final filled = percent > 0 && percent < 100 ? percent / 100 : null;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.graphic_eq, size: 48, color: mochaMauve),
          const SizedBox(height: 16),
          Text(
            label,
            style: const TextStyle(
              color: mochaText,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 320,
            child: LinearProgressIndicator(
              minHeight: 6,
              value: filled,
              color: mochaMauve,
              backgroundColor: mochaMauve.withValues(alpha: 0.20),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _statusLine(percent, startedAt),
            style: const TextStyle(
              color: mochaSubtext0,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the "NN% · ~Xm left" line under the bar. Until enough progress has
  /// accrued to fit a stable rate there is nothing to extrapolate from, so it
  /// shows only "Estimating…" beside the percent. Once a pass finishes the
  /// placeholder is unmounted and this widget returns an empty line.
  String _statusLine(int percent, DateTime? startedAt) {
    final percentText = percent > 0 ? '$percent%' : '0%';
    if (percent <= 0 || percent >= 100 || startedAt == null) {
      return percent <= 0 ? '' : percentText;
    }
    // Average the rate over the rolling window (slope between its span's
    // endpoints) rather than the instantaneous jump, which is lumpy.
    final rate = _samples.smoothedRate();
    if (rate == null || rate <= 0) {
      return '$percentText · ~Estimating…';
    }
    final remaining = 100 - percent;
    final etaSeconds = remaining / rate;
    final etaText = _formatDuration(Duration(seconds: etaSeconds.round()));
    return '$percentText · ~$etaText left';
  }

  static String _formatDuration(Duration d) {
    if (d.inSeconds < 45) return '${d.inSeconds < 1 ? 1 : d.inSeconds}s';
    if (d.inMinutes > 60) return '${d.inMinutes ~/ 60}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }
}

/// Bounded FIFO of (elapsedSeconds, percent) progress samples. The smoothed
/// rate is the slope across the oldest->newest sample in the rolling window, so
/// brief stalls or bursts are damped instead of dominating the estimate.
class _Samples {
  final int maxLength;
  final List<(double, int)> _items = [];

  _Samples({required this.maxLength});

  bool get isEmpty => _items.isEmpty;

  void record(double elapsed, int percent) {
    _items.add((elapsed, percent));
    if (_items.length > maxLength) _items.removeAt(0);
  }

  /// Percent-per-second slope across the oldest->newest sample, or null if there
  /// are not enough distinct points to be meaningful.
  double? smoothedRate() {
    if (_items.length < 2) return null;
    final first = _items.first;
    final last = _items.last;
    final dt = last.$1 - first.$1;
    if (dt <= 0) return null;
    final rate = (last.$2 - first.$2) / dt;
    return rate;
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
