import 'package:flutter/material.dart';

import '../models/transcript_segment.dart';
import '../theme/app_theme.dart';
import '../utils/format_duration.dart';

class TranscriptSegmentTile extends StatelessWidget {
  final TranscriptSegment segment;
  final bool isActive;
  final bool showSpeakerLabel;
  final VoidCallback onTap;

  const TranscriptSegmentTile({
    super.key,
    required this.segment,
    required this.isActive,
    required this.showSpeakerLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        button: true,
        label: '${segment.speakerLabel == null ? '' : '${segment.speakerLabel} '}'
            '${formatDuration(segment.fromTs)} ${segment.text}',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: isActive ? mochaMauve.withValues(alpha: 0.10) : null,
            border: isActive
                ? const Border(left: BorderSide(color: mochaMauve, width: 3))
                : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showSpeakerLabel)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      if (segment.speakerLabel != null) ...[
                        Text(
                          segment.speakerLabel!,
                          style: const TextStyle(
                            color: mochaSubtext1,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        formatDuration(segment.fromTs),
                        style: const TextStyle(
                          color: mochaOverlay0,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                segment.text,
                style: TextStyle(
                  color: isActive ? mochaText : mochaSubtext1,
                  fontSize: 16,
                  height: 1.5,
                  fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
