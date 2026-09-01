import 'package:flutter_test/flutter_test.dart';
import 'package:solutionscribe/services/transcription_service.dart';
// ignore: implementation_imports
import 'package:whisper_ggml/src/models/responses/whisper_transcribe_segment.dart';

WhisperTranscribeSegment _word(String text, int ms) {
  return WhisperTranscribeSegment(
    text: text,
    fromTs: Duration(milliseconds: ms),
    toTs: Duration(milliseconds: ms + 200),
  );
}

void main() {
  test('single sentence groups into one chunk', () {
    final words = [
      _word('Hello', 0),
      _word('world.', 250),
    ];
    final groups = TranscriptionService.groupWordSegments(words);
    expect(groups.length, 1);
    expect(groups.single.text, 'Hello world.');
    expect(groups.single.fromTs, Duration(milliseconds: 0));
    expect(groups.single.toTs, Duration(milliseconds: 450));
  });

  test('sentence-ending punctuation splits groups', () {
    final words = [
      _word('First', 0),
      _word('sentence.', 250),
      _word('Second', 600),
      _word('one.', 800),
    ];
    final groups = TranscriptionService.groupWordSegments(words);
    expect(groups.length, 2);
    expect(groups[0].text, 'First sentence.');
    expect(groups[1].text, 'Second one.');
  });

  test('a pause longer than 300ms splits groups', () {
    final words = [
      _word('One', 0),
      _word('two', 250),
      _word('three', 4000), // 3.75s gap after "two"
    ];
    final groups = TranscriptionService.groupWordSegments(words);
    expect(groups.length, 2);
    expect(groups[0].text, 'One two');
    expect(groups[1].text, 'three');
  });

  test('long runs are capped by maxWords', () {
    final words = [
      for (var i = 0; i < 25; i++) _word('w$i', i * 100),
    ];
    final groups = TranscriptionService.groupWordSegments(words);
    // 25 words capped at 20 per group -> two groups.
    expect(groups.length, 2);
    expect(groups[0].text.split(' ').length, 20);
    expect(groups[1].text.split(' ').length, 5);
  });

  test('blank segments are skipped', () {
    final words = [
      _word('Only', 0),
      _word(' ', 250),
      _word('real', 400),
      _word('words', 600),
    ];
    final groups = TranscriptionService.groupWordSegments(words);
    expect(groups.length, 1);
    expect(groups.single.text, 'Only real words');
  });
}
