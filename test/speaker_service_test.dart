import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:solutionscribe/services/speaker_service.dart';

Float32List _vec(List<double> values) => Float32List.fromList(values);

void main() {
  final speakerA = _vec([1, 1, 1, 1, 0, 0, 0, 0]);
  final speakerB = _vec([0, 0, 0, 0, 1, 1, 1, 1]);
  final speakerC = _vec([0, 0, 0, 0, 0, 0, 1, 1]);

  test('clusters alternating speakers by first-appearance order', () {
    final ids = SpeakerService.assignSpeakers([
      speakerA,
      speakerB,
      speakerC,
      speakerA,
      speakerB,
      speakerC,
    ]);

    expect(ids, [0, 1, 2, 0, 1, 2]);
  });

  test('identical embeddings collapse into one cluster', () {
    final ids = SpeakerService.assignSpeakers([
      speakerA,
      speakerA,
      speakerA,
    ]);

    expect(ids, [0, 0, 0]);
  });

  test('null embeddings stay null and do not affect neighbours', () {
    final ids = SpeakerService.assignSpeakers([
      null,
      speakerA,
      speakerA,
      null,
      speakerB,
    ]);

    expect(ids[0], isNull);
    expect(ids[1], 0);
    expect(ids[2], 0);
    expect(ids[3], isNull);
    // speakerB is far enough from A to start its own cluster.
    expect(ids[4], 1);
  });

  test('threshold separates near but distinct speakers', () {
    final a = _vec([1, 0, 0, 0, 0, 0, 0, 0]);
    final nearlyA = _vec([0.95, 0.312, 0, 0, 0, 0, 0, 0]);

    // Above the default threshold they merge…
    expect(
      SpeakerService.assignSpeakers([a, nearlyA]),
      [0, 0],
    );

    // …but a stricter threshold splits them.
    expect(
      SpeakerService.assignSpeakers([a, nearlyA], threshold: 0.98),
      [0, 1],
    );
  });

  test('empty embedding lists yield nulls only', () {
    expect(SpeakerService.assignSpeakers([null, null]), [null, null]);
    expect(SpeakerService.assignSpeakers([]), isEmpty);
  });
}