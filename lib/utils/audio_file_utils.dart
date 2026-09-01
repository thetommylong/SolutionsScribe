const Set<String> supportedAudioExtensions = {'mp3', 'wav', 'm4a'};

bool isSupportedAudioFile(String path) {
  final ext = path.split('.').last.toLowerCase();
  return supportedAudioExtensions.contains(ext);
}

String fileNameFromPath(String path) {
  return path.split('/').last;
}
