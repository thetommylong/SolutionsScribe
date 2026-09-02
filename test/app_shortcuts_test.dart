import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solutionscribe/components/app_shortcuts.dart';
import 'package:solutionscribe/components/volume_control.dart';
import 'package:solutionscribe/providers/app_state_provider.dart';
import 'package:solutionscribe/providers/volume_provider.dart';
import 'package:solutionscribe/services/audio_player_service.dart';

class _FakeAudioPlayerService implements AudioPlayerService {
  double? lastVolume;

  @override
  bool get isLinux => false;

  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<bool> get playingStream => const Stream.empty();

  @override
  Duration get position => Duration.zero;
  @override
  Duration get duration => Duration.zero;
  @override
  bool get playing => false;

  @override
  Future<void> loadFile(String path) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> togglePlayPause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async => lastVolume = volume;
  @override
  Future<void> skipForward([Duration duration = const Duration(seconds: 30)]) async {}
  @override
  Future<void> skipBackward([Duration duration = const Duration(seconds: 10)]) async {}
  @override
  void dispose() {}
}

class _ReadyAppStateNotifier extends AppStateNotifier {
  _ReadyAppStateNotifier(super.ref) : super() {
    state = const AppState(stage: AppStage.ready);
  }
}

void main() {
  testWidgets(
      'CallbackShortcuts fires when the autofocus node is a descendant',
      (tester) async {
    var fired = false;
    await tester.pumpWidget(
      CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): () => fired = true,
        },
        // Focus must be INSIDE the shortcuts' subtree (an autofocus node on an
        // ancestor would swallow the key events before they reach it).
        child: Focus(autofocus: true, child: const SizedBox()),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(fired, isTrue, reason: 'space shortcut should have fired');
  });

  testWidgets('AppShortcuts arrow-down lowers volume', (tester) async {
    final audio = _FakeAudioPlayerService();
    final container = ProviderContainer(overrides: [
      appStateProvider.overrideWith((ref) => _ReadyAppStateNotifier(ref)),
      audioPlayerServiceProvider.overrideWithValue(audio),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AppShortcuts(child: SizedBox()),
      ),
    );

    expect(container.read(volumeProvider), 1.0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(container.read(volumeProvider), closeTo(0.9, 0.0001));
    expect(audio.lastVolume, closeTo(0.9, 0.0001));
  });

  testWidgets('AppShortcuts arrow-up raises volume', (tester) async {
    final audio = _FakeAudioPlayerService();
    final container = ProviderContainer(overrides: [
      appStateProvider.overrideWith((ref) => _ReadyAppStateNotifier(ref)),
      audioPlayerServiceProvider.overrideWithValue(audio),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AppShortcuts(child: SizedBox()),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    // 1.0 + 0.1 clamps at 1.0 (already at max), so no setVolume call.
    expect(container.read(volumeProvider), 1.0);
    expect(audio.lastVolume, isNull);
  });

  testWidgets('VolumeControl shows the current percentage in its tooltip',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: Center(child: VolumeControl())),
        ),
      ),
    );

    final sliderWrap = find.byWidgetPredicate(
      (w) => w is Tooltip && w.message == 'Volume 100%',
    );
    expect(sliderWrap, findsOneWidget);
  });
}