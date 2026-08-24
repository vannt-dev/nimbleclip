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
    final provider = SettingsProvider();
    await provider.initialized;

    await provider.setAllowExternalServices(false);
    await provider.setRemoveCacheAfterGallery(true);
    await provider.setMaxConcurrentDownloads(5);

    final restored = SettingsProvider();
    await restored.initialized;
    expect(restored.allowExternalServices, isFalse);
    expect(ExternalServicePolicy.allowExternalServices, isFalse);
    expect(restored.removeCacheAfterGallery, isTrue);
    expect(restored.maxConcurrentDownloads, 5);

    ExternalServicePolicy.allowExternalServices = true;
  });

  test('clamps simultaneous downloads to the supported range', () async {
    final provider = SettingsProvider();
    await provider.initialized;
    await provider.setMaxConcurrentDownloads(99);
    expect(provider.maxConcurrentDownloads, 5);
    await provider.setMaxConcurrentDownloads(-1);
    expect(provider.maxConcurrentDownloads, 1);
  });
}
