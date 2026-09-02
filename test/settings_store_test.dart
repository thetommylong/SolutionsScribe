import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solutionscribe/services/settings_store.dart';

void main() {
  late Directory tempDir;
  late SettingsStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('settings_store_test');
    store = SettingsStore(supportDirOverride: tempDir.path);
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('isModelAcknowledged is false before any marker exists', () async {
    expect(await store.isModelAcknowledged(), isFalse);
  });

  test('markModelAcknowledged creates a 0-byte marker file', () async {
    await store.markModelAcknowledged();

    final file = File('${tempDir.path}${Platform.pathSeparator}'
        '${SettingsStore.modelAckFileName}');
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), 0);
  });

  test('isModelAcknowledged is true after marking, and persists', () async {
    await store.markModelAcknowledged();
    expect(await store.isModelAcknowledged(), isTrue);

    // A fresh store reading the same directory still sees the marker.
    final reopened = SettingsStore(supportDirOverride: tempDir.path);
    expect(await reopened.isModelAcknowledged(), isTrue);
  });

  test('acknowledgement survives an app "restart" via the marker file', () async {
    await store.markModelAcknowledged();
    final newStore = SettingsStore(supportDirOverride: tempDir.path);
    expect(await newStore.isModelAcknowledged(), isTrue);
  });

  test('loadPreferences is empty before anything is saved', () async {
    expect(await store.loadPreferences(), isEmpty);
  });

  test('savePreferences round-trips through the JSON file', () async {
    await store.savePreferences({
      'model': 'small',
      'partGapSeconds': 3.5,
      'showTranscriptByDefault': true,
    });

    // A fresh store reading the same directory sees the persisted values.
    final reopened = SettingsStore(supportDirOverride: tempDir.path);
    final prefs = await reopened.loadPreferences();
    expect(prefs['model'], 'small');
    expect(prefs['partGapSeconds'], 3.5);
    expect(prefs['showTranscriptByDefault'], isTrue);
  });

  test('loadPreferences tolerates a corrupt settings file', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}'
        '${SettingsStore.settingsFileName}');
    await file.parent.create(recursive: true);
    await file.writeAsString('this is not json {');

    expect(await store.loadPreferences(), isEmpty);
  });
}
