import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum ControlState { default_, hovered, clicked }

class PlaybackControls extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onSkipBack;
  final VoidCallback onSkipForward;

  const PlaybackControls({
    super.key,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onSkipBack,
    required this.onSkipForward,
  });

  @override
  State<PlaybackControls> createState() => _PlaybackControlsState();
}

class _PlaybackControlsState extends State<PlaybackControls> {
  final Map<String, ControlState> _states = {
    'back': ControlState.default_,
    'play': ControlState.default_,
    'forward': ControlState.default_,
  };

  Widget _buildButton({
    required String key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final state = _states[key]!;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() {
        if (_states[key] == ControlState.default_) {
          _states[key] = ControlState.hovered;
        }
      }),
      onExit: (_) => setState(() {
        if (_states[key] == ControlState.hovered) {
          _states[key] = ControlState.default_;
        }
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _states[key] = ControlState.clicked),
        onTapUp: (_) => setState(() => _states[key] = ControlState.hovered),
        onTapCancel: () =>
            setState(() => _states[key] = ControlState.default_),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: state == ControlState.default_
                  ? Colors.transparent
                  : mochaMauve.withValues(alpha: state == ControlState.clicked
                      ? 0.7
                      : 1.0),
              borderRadius: BorderRadius.circular(
                state == ControlState.clicked ? 12 : 8,
              ),
            ),
            child: Semantics(
              label: tooltip,
              button: true,
              excludeSemantics: true,
              child: Icon(
                icon,
                size: 20,
                color: state == ControlState.default_
                    ? mochaText
                    : mochaBase,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildButton(
          key: 'back',
          icon: Icons.fast_rewind_rounded,
          tooltip: 'Skip back',
          onTap: widget.onSkipBack,
        ),
        const SizedBox(width: 4),
        _buildButton(
          key: 'play',
          icon: widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          tooltip: widget.isPlaying ? 'Pause' : 'Play',
          onTap: widget.onPlayPause,
        ),
        const SizedBox(width: 4),
        _buildButton(
          key: 'forward',
          icon: Icons.fast_forward_rounded,
          tooltip: 'Skip forward',
          onTap: widget.onSkipForward,
        ),
      ],
    );
  }
}
