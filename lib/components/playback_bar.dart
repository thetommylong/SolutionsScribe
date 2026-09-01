import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_state_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import 'playback_controls.dart';
import 'wavy_seek_bar.dart';

class PlaybackBar extends ConsumerWidget {
  const PlaybackBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioService = ref.watch(audioPlayerServiceProvider);
    final track = ref.watch(
      appStateProvider.select((s) => s.track),
    );

    final position = ref.watch(audioPositionProvider).value ?? Duration.zero;
    final duration =
        ref.watch(audioDurationProvider).value ?? track?.duration ?? Duration.zero;
    final isPlaying = ref.watch(audioPlayingProvider).value ?? false;

    return Container(
      height: 64,
      color: mochaMantle,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      // Absorb pointer events across the whole footer so clicks/drags on blank
      // areas never fall through to the transcript list behind it.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Row(
        children: [
          // Metadata box (fixed 200px)
          SizedBox(
            width: 200,
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: mochaSurface0,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.music_note,
                    color: mochaSubtext0,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track?.title ?? 'No track',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: mochaText,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                      Text(
                        track?.subtitle ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: mochaSubtext0,
                          fontSize: 9,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Center: wavy seek bar
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: WavySeekBar(
                position: position,
                total: duration,
                onSeek: (target) => audioService.seek(target),
              ),
            ),
          ),
          // Right: playback controls
          PlaybackControls(
            isPlaying: isPlaying,
            onPlayPause: () => audioService.togglePlayPause(),
            onSkipBack: () => audioService.skipBackward(
              Duration(seconds: ref.read(skipBackSecondsProvider)),
            ),
            onSkipForward: () => audioService.skipForward(
              Duration(seconds: ref.read(skipForwardSecondsProvider)),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
