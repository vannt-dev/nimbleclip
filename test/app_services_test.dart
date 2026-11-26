import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/app_services.dart';
import 'package:nimble_clip/services/quick_share_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentShareEntry implements QuickShareChannel {
  @override
  Stream<String> get shares => const Stream.empty();

  @override
  Future<void> setTargetEnabled(bool enabled) async {}

  @override
  Future<void> showMessage(String message) async {}

  @override
  Future<void> releaseKeepAlive() async {}

  @override
  Future<void> requestNotifications() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory.systemTemp.path,
        );
  });

  // One test only: the native download gateway claims a process-wide stream,
  // so a second set of services in this file could not listen to it.
  test('settings reach the download list with no widget tree', () async {
    final services = AppServices(quickShare: _SilentShareEntry());
    await services.settings.initialized;

    await services.settings.setMaxConcurrentDownloads(5);
    await services.settings.setSaveLyrics(true);
    await services.settings.setConvertAudioToMp3(true);

    // What Quick download relies on when the app starts without a screen.
    expect(services.downloads.maxConcurrentDownloads, 5);
    expect(services.downloads.saveLyrics, isTrue);
    expect(services.downloads.convertAudioToMp3, isTrue);
    await services.quickDownloads.dispose();
  });
}
