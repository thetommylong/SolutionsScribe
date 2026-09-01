class TranscriptSegment {
  final String text;
  final Duration fromTs;
  final Duration toTs;

  /// Display label for the speaker ("Speaker 1", "Speaker 2", …), or null
  /// when speaker identification was unavailable. Null labels are hidden.
  final String? speakerLabel;

  const TranscriptSegment({
    required this.text,
    required this.fromTs,
    required this.toTs,
    this.speakerLabel,
  });

  Duration get duration => toTs - fromTs;

  bool containsTime(Duration time) =>
      time >= fromTs && time <= toTs;
}

class TranscriptPart {
  final int index;
  final List<TranscriptSegment> segments;

  const TranscriptPart({required this.index, required this.segments});

  String get label => 'Part ${index + 1}';
}
