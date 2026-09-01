import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/volume_provider.dart';
import '../theme/app_theme.dart';

/// Volume icon + slider, placed in the playback bar. Icon tap toggles mute and
/// raises the on-screen display; dragging the slider applies live (no OSD).
class VolumeControl extends ConsumerWidget {
  const VolumeControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final volume = ref.watch(volumeProvider);
    final muted = volume == 0.0;

    final IconData icon;
    if (muted) {
      icon = Icons.volume_off_outlined;
    } else if (volume < 0.5) {
      icon = Icons.volume_down_outlined;
    } else {
      icon = Icons.volume_up_outlined;
    }

    return Semantics(
      container: true,
      label: 'Volume ${(volume * 100).round()}%',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: muted ? 'Unmute' : 'Mute',
            child: InkWell(
              onTap: () => ref.read(volumeProvider.notifier).toggleMute(),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Semantics(
                  label: muted ? 'Unmute' : 'Mute',
                  button: true,
                  excludeSemantics: true,
                  child: Icon(icon, size: 20, color: mochaSubtext0),
                ),
              ),
            ),
          ),
          Tooltip(
            message: 'Volume',
            child: SizedBox(
              width: 72,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 10),
                ),
                child: Slider(
                  value: volume,
                  onChanged: (v) =>
                      ref.read(volumeProvider.notifier).set(v),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}