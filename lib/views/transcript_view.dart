import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/playback_bar.dart';
import '../components/transcript_list.dart';
import '../providers/app_state_provider.dart';
import '../services/window_service.dart';
import '../theme/app_theme.dart';

class TranscriptView extends ConsumerStatefulWidget {
  const TranscriptView({super.key});

  @override
  ConsumerState<TranscriptView> createState() => _TranscriptViewState();
}

class _TranscriptViewState extends ConsumerState<TranscriptView> {
  @override
  void initState() {
    super.initState();
    // "Resize once the media hits": size the window appropriately for the
    // playback screen as soon as we arrive (full height when the transcript is
    // shown, compact chrome+status when it autohides). Post-frame so the resize
    // lands predictably after layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final visible = ref.read(transcriptVisibleProvider);
      unawaited(WindowService.instance.enterTranscript(
        transcriptVisible: visible,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final transcriptVisible = ref.watch(transcriptVisibleProvider);
    final isTranscribing =
        ref.watch(appStateProvider.select((s) => s.isTranscribing));
    final hasParts =
        ref.watch(appStateProvider.select((s) => s.parts.isNotEmpty));
    final transcribeError =
        ref.watch(appStateProvider.select((s) => s.transcribeError));

    // Resize the window to fit when the transcript is shown/hidden, so hiding
    // it doesn't leave a blank transcript region (and sets the header chrome).
    ref.listen(transcriptVisibleProvider, (prev, next) {
      unawaited(WindowService.instance.setTranscriptVisible(next));
    });

    return Scaffold(
      backgroundColor: mochaBase,
      body: Column(
        children: [
          _Header(
            onBack: () {
              // Stop playback before leaving the player so audio doesn't keep
              // playing after the transcript screen closes.
              ref.read(audioPlayerServiceProvider).pause();
              ref.read(appStateProvider.notifier).reset();
              // Back on the upload/main screen, restore a reasonable window.
              unawaited(WindowService.instance.leaveTranscript());
            },
          ),
          if (transcribeError != null)
            _StatusBanner(
              message: 'Transcription failed: $transcribeError',
              color: mochaRed,
            ),
          // The transcribing status strip is ALWAYS visible while a background
          // pass runs, regardless of the transcript hide/show toggle.
          if (isTranscribing) const _TranscribingStrip(),
          if (transcriptVisible) ...[
            if (isTranscribing && !hasParts)
              const Expanded(child: _TranscribingHint())
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

/// Slim, always-visible status row shown while a background transcription pass
/// is running — independent of the transcript hide/show toggle, so the user
/// always knows work is in progress. Carries the phase label and the single
/// stylish progress bar with a live, smoothed time-remaining estimate.
class _TranscribingStrip extends ConsumerStatefulWidget {
  const _TranscribingStrip();

  @override
  ConsumerState<_TranscribingStrip> createState() => _TranscribingStripState();
}

class _TranscribingStripState extends ConsumerState<_TranscribingStrip> {
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

    // Seed the sample window with the first datum so an estimate is reachable
    // as soon as progress begins.
    if (_samples.isEmpty && startedAt != null) {
      _samples.record(_secondsSince(startedAt, DateTime.now()), percent);
    }

    return Container(
      height: WindowService.stripHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: const BoxDecoration(
        color: mochaMantle,
        border: Border(bottom: BorderSide(color: mochaSurface0, width: 1)),
      ),
      child: Row(
        children: [
          const _PulsingIcon(),
          const SizedBox(width: 12),
          Text(
            phase ?? 'Transcribing…',
            style: const TextStyle(
              color: mochaText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StylishProgressBar(
              value: percent > 0 && percent < 100 ? percent / 100 : null,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$percent%',
                style: const TextStyle(
                  color: mochaText,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                _etaLine(percent, startedAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: mochaSubtext0,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Builds the ETA caption ("~Xm left" / "~Estimating…") under the percent.
  /// Until enough progress accrues to fit a stable rate there is nothing to
  /// extrapolate from, so it shows only "Estimating…". Once the pass finishes
  /// the strip is unmounted.
  String _etaLine(int percent, DateTime? startedAt) {
    // Nothing to extrapolate from before progress starts or after it finishes.
    if (percent <= 0 || percent >= 100 || startedAt == null) {
      return '';
    }
    final rate = _samples.smoothedRate();
    if (rate == null || rate <= 0) {
      return '~Estimating…';
    }
    final remaining = 100 - percent;
    final etaSeconds = remaining / rate;
    return '~${_formatDuration(Duration(seconds: etaSeconds.round()))} left';
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

  /// Percent-per-second slope across the oldest->newest sample, or null if
  /// there are not enough distinct points to be meaningful.
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

/// A gently bobbing equalizer icon that signals live transcription work.
class _PulsingIcon extends StatefulWidget {
  const _PulsingIcon();

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(_controller),
      child: const Icon(Icons.graphic_eq, size: 22, color: mochaMauve),
    );
  }
}

/// A single, decorative centered visual shown in the transcript region while a
/// pass runs but before any parts arrive. It carries no progress bar — that
/// lives in the always-visible [_TranscribingStrip] above — so there is never
/// a duplicated bar; this just fills the region while it has no content.
class _TranscribingHint extends StatelessWidget {
  const _TranscribingHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.graphic_eq, size: 44, color: mochaMauve),
          const SizedBox(height: 14),
          Text(
            'Building transcript…',
            style: const TextStyle(
              color: mochaSubtext0,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Polished linear progress bar: a rounded track with a solid accent fill and
/// a soft left-to-right shimmer sweep. When [value] is null it renders an
/// indeterminate shimmer (no fill segment), used before progress is known.
class _StylishProgressBar extends StatefulWidget {
  final double? value;

  const _StylishProgressBar({this.value});

  @override
  State<_StylishProgressBar> createState() => _StylishProgressBarState();
}

class _StylishProgressBarState extends State<_StylishProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: AnimatedBuilder(
          animation: _shimmer,
          builder: (context, _) {
            final t = _shimmer.value;
            final fill = value ?? 0.0;
            return Stack(
              fit: StackFit.expand,
              children: [
                // Track.
                ColoredBox(color: mochaSurface0),
                // Fill.
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fill,
                  child: const ColoredBox(color: mochaMauve),
                ),
                // Shimmer sweep across the whole bar for indeterminate feel.
                if (value == null)
                  Positioned(
                    left: -60 + t * 120,
                    width: 40,
                    top: 0,
                    bottom: 0,
                    child: const _BarSheen(),
                  )
                else
                  Positioned(
                    left: -60 + ((t * 130) - 30),
                    width: 40,
                    top: 0,
                    bottom: 0,
                    child: const _BarSheen(),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BarSheen extends StatelessWidget {
  const _BarSheen();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.35),
            Colors.white.withValues(alpha: 0.0),
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
