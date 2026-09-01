class AudioTrack {
  final String filePath;
  final String title;
  final String subtitle;
  final Duration duration;

  const AudioTrack({
    required this.filePath,
    required this.title,
    this.subtitle = '',
    this.duration = Duration.zero,
  });
}
