import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/core/constants/app_constants.dart';
import 'package:nimble_clip/core/utils/external_service_policy.dart';
import 'package:nimble_clip/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  test('uses the device locale by default', () async {
    final provider = SettingsProvider();
    await provider.initialized;

    expect(provider.locale, isNull);
  });

  test('Save audio as MP3 is off by default and remembered', () async {
    final provider = SettingsProvider();
    await provider.initialized;
    expect(provider.convertAudioToMp3, isFalse);

    await provider.setConvertAudioToMp3(true);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AppConstants.keyConvertAudioToMp3), isTrue);
    final restored = SettingsProvider();
    await restored.initialized;
    expect(restored.convertAudioToMp3, isTrue);
  });

  test('Wi-Fi only downloads is off by default and remembered', () async {
    final provider = SettingsProvider();
    await provider.initialized;
    expect(provider.wifiOnlyDownloads, isFalse);

    await provider.setWifiOnlyDownloads(true);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AppConstants.keyWifiOnlyDownloads), isTrue);
    final restored = SettingsProvider();
    await restored.initialized;
    expect(restored.wifiOnlyDownloads, isTrue);
  });

  test('persists and restores an explicit locale', () async {
    final provider = SettingsProvider();
    await provider.initialized;
    await provider.setLocale(const Locale('vi'));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AppConstants.keyLanguageCode), 'vi');

    final restored = SettingsProvider();
    await restored.initialized;
    expect(restored.locale, const Locale('vi'));
  });

  test('clears the preference when device language is selected', () async {
    SharedPreferences.setMockInitialValues({
      AppConstants.keyLanguageCode: 'vi',
    });
    final provider = SettingsProvider();
    await provider.initialized;
    await provider.setLocale(null);

    final prefs = await SharedPreferences.getInstance();
    expect(provider.locale, isNull);
    expect(prefs.containsKey(AppConstants.keyLanguageCode), isFalse);
  });

  test('persists download, storage, and external-service controls', () async {
    final policy = ExtractionPolicy();
    final provider = SettingsProvider(extractionPolicy: policy);
    await provider.initialized;

    await provider.setAllowExternalServices(false);
    await provider.setRemoveCacheAfterGallery(true);
    await provider.setMaxConcurrentDownloads(5);

    final restored = SettingsProvider(extractionPolicy: policy);
    await restored.initialized;
    expect(restored.allowExternalServices, isFalse);
    expect(policy.allowExternalServices, isFalse);
    expect(restored.removeCacheAfterGallery, isTrue);
    expect(restored.maxConcurrentDownloads, 5);
  });

  test('clamps simultaneous downloads to the supported range', () async {
    final provider = SettingsProvider();
    await provider.initialized;
    await provider.setMaxConcurrentDownloads(99);
    expect(provider.maxConcurrentDownloads, 5);
    await provider.setMaxConcurrentDownloads(-1);
    expect(provider.maxConcurrentDownloads, 1);
  });

  test('measures the local copies with the given reader', () async {
    final provider = SettingsProvider(measureLocalCopies: () async => 2048);
    await provider.initialized;

    expect(provider.cacheSizeBytes, 2048);
  });

  test('a refresh asked for mid-measure runs once more, and wins', () async {
    final measures = <Completer<int>>[];
    final provider = SettingsProvider(
      measureLocalCopies: () {
        final measure = Completer<int>();
        measures.add(measure);
        return measure.future;
      },
    );
    await Future<void>.delayed(Duration.zero);
    expect(measures, hasLength(1));

    // Two downloads finishing while the first walk is still running.
    final first = provider.refreshCacheSize();
    final second = provider.refreshCacheSize();
    measures[0].complete(100);
    await Future<void>.delayed(Duration.zero);
    expect(measures, hasLength(2), reason: 'one more walk, not one per ask');
    measures[1].complete(300);
    await Future.wait<void>([first, second, provider.initialized]);

    expect(provider.cacheSizeBytes, 300);
    expect(measures, hasLength(2));
  });

  test('a failed measure keeps the last size instead of throwing', () async {
    var fail = false;
    final provider = SettingsProvider(
      measureLocalCopies: () async {
        if (fail) throw const FileSystemException('gone');
        return 512;
      },
    );
    await provider.initialized;
    fail = true;

    await provider.refreshCacheSize();

    expect(provider.cacheSizeBytes, 512);
  });
}
