const Set<String> supportedAudioExtensions = {'mp3', 'wav', 'm4a'};

bool isSupportedAudioFile(String path) {
  final ext = path.split('.').last.toLowerCase();
  return supportedAudioExtensions.contains(ext);
}

String fileNameFromPath(String path) {
  // Handle both POSIX and Windows separators.
  final lastSlash = path.lastIndexOf('/');
  final lastBackslash = path.lastIndexOf('\\');
  final idx = lastSlash > lastBackslash ? lastSlash : lastBackslash;
  return idx >= 0 ? path.substring(idx + 1) : path;
}
