import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class WavySeekBar extends StatefulWidget {
  final Duration position;
  final Duration total;
  final ValueChanged<Duration> onSeek;
  final bool enabled;

  const WavySeekBar({
    super.key,
    required this.position,
    required this.total,
    required this.onSeek,
    this.enabled = true,
  });

  @override
  State<WavySeekBar> createState() => _WavySeekBarState();
}

class _WavySeekBarState extends State<WavySeekBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _dragging = false;
  double _dragValue = 0;
  double _width = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _progress {
    if (widget.total == Duration.zero) return 0;
    final p = widget.position.inMilliseconds / widget.total.inMilliseconds;
    return p.clamp(0.0, 1.0);
  }

  Duration _durationForValue(double value) =>
      Duration(milliseconds: (value * widget.total.inMilliseconds).round());

  void _syncDragPos(double dx) {
    setState(() {
      _dragValue = (dx / _width).clamp(0.0, 1.0);
    });
  }

  void _endDrag() {
    setState(() => _dragging = false);
    widget.onSeek(_durationForValue(_dragValue));
  }

  void _seekAt(double dx) {
    widget.onSeek(_durationForValue((dx / _width).clamp(0.0, 1.0)));
  }

  @override
  Widget build(BuildContext context) {
    final active = _dragging ? _dragValue : _progress;

    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;

        return GestureDetector(
          onTapDown: widget.enabled
              ? (details) => _seekAt(details.localPosition.dx)
              : null,
          onHorizontalDragStart: widget.enabled
              ? (details) {
                  setState(() => _dragging = true);
                  _syncDragPos(details.localPosition.dx);
                }
              : null,
          onHorizontalDragUpdate: widget.enabled
              ? (details) => _syncDragPos(details.localPosition.dx)
              : null,
          onHorizontalDragEnd: widget.enabled
              ? (_) => _endDrag()
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return CustomPaint(
                    size: Size(constraints.maxWidth, 36),
                    painter: _WavySeekBarPainter(
                      progress: active,
                      wavePhase: _controller.value * 2 * math.pi,
                    ),
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formatSeekTime(_durationForValue(active)),
                      style: const TextStyle(
                        color: mochaText,
                        fontSize: 9,
                        height: 1,
                      ),
                    ),
                    Text(
                      formatSeekTime(widget.total),
                      style: const TextStyle(
                        color: mochaText,
                        fontSize: 9,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

String formatSeekTime(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

class _WavySeekBarPainter extends CustomPainter {
  final double progress;
  final double wavePhase;
  static const double _waveHeight = 12;
  static const double _thickness = 4;
  static const double _wavelength = 40;

  _WavySeekBarPainter({required this.progress, required this.wavePhase});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final centerY = size.height / 2;
    final amplitude = _waveHeight / 2;
    final cutX = size.width * progress;

    // Unplayed portion: a static flat line (no wiggle).
    if (cutX < size.width) {
      canvas.drawLine(
        Offset(cutX, centerY),
        Offset(size.width, centerY),
        Paint()
          ..color = mochaSurface2
          ..strokeWidth = _thickness
          ..strokeCap = StrokeCap.round,
      );
    }

    // Played portion: animated wiggle, clipped to progress so it stops at
    // the current position. Fades in from the left edge so the wave doesn't
    // look like it begins mid-sine "out of nowhere" once playback is far in.
    if (cutX > 1) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, cutX, size.height));
      final playPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _thickness
        ..strokeCap = StrokeCap.round;
      final fadeLen = math.min(24.0, cutX);
      playPaint.shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [mochaMauve.withValues(alpha: 0), mochaMauve],
      ).createShader(Rect.fromLTWH(0, 0, fadeLen, size.height));
      _drawWave(canvas, size, centerY, amplitude, 0, size.width, playPaint);
      canvas.restore();
    }

    // Thumb
    final thumbX = cutX.clamp(0.0, size.width);
    final thumbY = centerY;
    canvas.drawCircle(
      Offset(thumbX, thumbY),
      6,
      Paint()
        ..color = mochaMauve
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(thumbX, thumbY),
      2.5,
      Paint()
        ..color = mochaBase
        ..style = PaintingStyle.fill,
    );
  }

  void _drawWave(
    Canvas canvas,
    Size size,
    double centerY,
    double amplitude,
    double startX,
    double endX,
    Paint paint,
  ) {
    final path = Path();
    var started = false;

    for (var x = startX; x <= endX; x += 1.0) {
      final wave = math.sin((x / _wavelength) * 2 * math.pi + wavePhase);
      final y = centerY + wave * amplitude;
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavySeekBarPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.wavePhase != wavePhase;
}
