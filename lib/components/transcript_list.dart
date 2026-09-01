import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/transcript_segment.dart';
import '../providers/app_state_provider.dart';
import '../theme/app_theme.dart';
import 'transcript_segment_tile.dart';

class _ListEntry {
  final bool isHeader;
  final String? headerText;
  final TranscriptSegment? segment;
  final bool showSpeakerLabel;
  final int flatIndex;

  const _ListEntry.header(this.headerText)
      : isHeader = true,
        segment = null,
        showSpeakerLabel = false,
        flatIndex = -1;

  const _ListEntry.segment(this.segment, this.showSpeakerLabel, this.flatIndex)
      : isHeader = false,
        headerText = null;
}

class TranscriptList extends ConsumerStatefulWidget {
  const TranscriptList({super.key});

  @override
  ConsumerState<TranscriptList> createState() => _TranscriptListState();
}

class _TranscriptListState extends ConsumerState<TranscriptList> {
  final ScrollController _scrollController = ScrollController();
  int _lastActiveIndex = -1;
  final Map<int, GlobalKey> _segmentKeys = {};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int _activeFlatIndex(List<TranscriptPart> parts, Duration position) {
    var index = 0;
    for (final part in parts) {
      for (final segment in part.segments) {
        if (segment.containsTime(position)) return index;
        index++;
      }
    }
    return -1;
  }

  List<_ListEntry> _buildEntries(List<TranscriptPart> parts) {
    final entries = <_ListEntry>[];
    var flatIndex = 0;

    for (final part in parts) {
      entries.add(_ListEntry.header(part.label));
      TranscriptSegment? prev;

      for (final segment in part.segments) {
        final showLabel =
            prev == null || prev.speakerLabel != segment.speakerLabel;
        entries.add(_ListEntry.segment(segment, showLabel, flatIndex));
        prev = segment;
        flatIndex++;
      }
    }

    return entries;
  }

  void _followActive(int activeIndex) {
    if (activeIndex < 0) return;
    if (_lastActiveIndex == activeIndex) return;

    // Run after this build completes so the GlobalKey for the newly-active
    // segment has been created by the ListView's itemBuilder. If we check
    // synchronously here, the key doesn't exist yet and we bail (this is why
    // auto-scroll appeared broken).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _segmentKeys[activeIndex]?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      _lastActiveIndex = activeIndex;
    });
  }

  @override
  Widget build(BuildContext context) {
    final parts = ref.watch(appStateProvider.select((s) => s.parts));
    final audioService = ref.watch(audioPlayerServiceProvider);

    final position =
        ref.watch(audioPositionProvider).value ?? Duration.zero;

    final entries = _buildEntries(parts);
    final activeIndex = _activeFlatIndex(parts, position);
    _followActive(activeIndex);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(64),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        if (entry.isHeader) {
          return Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              entry.headerText!,
              style: const TextStyle(
                color: mochaText,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }

        final segment = entry.segment!;
        final flatIndex = entry.flatIndex;
        // Only the active segment gets a GlobalKey so we can auto-scroll to it.
        final key = flatIndex == activeIndex
            ? (_segmentKeys[flatIndex] ??= GlobalKey())
            : null;

        return TranscriptSegmentTile(
          key: key,
          segment: segment,
          isActive: flatIndex == activeIndex,
          showSpeakerLabel: entry.showSpeakerLabel,
          onTap: () => audioService.seek(segment.fromTs),
        );
      },
    );
  }
}