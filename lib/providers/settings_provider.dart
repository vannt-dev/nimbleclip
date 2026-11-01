import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/external_service_policy.dart';
import '../services/storage_service.dart';
import '../models/download_options.dart';

class SettingsProvider extends ChangeNotifier {
  final ExtractionPolicy _extractionPolicy;
  final Future<int> Function() _measureLocalCopies;
  ThemeMode _themeMode = ThemeMode.system;
  Locale? _locale;
  bool _autoSaveGallery = true;
  bool _autoPasteClipboard = true;
  String _preferredQuality = 'Highest'; // Highest, 720p, 480p, Ask
  int _cacheSizeBytes = 0;
  bool _allowExternalServices = true;
  bool _removeCacheAfterGallery = true;
  int _maxConcurrentDownloads = 3;
  bool _wifiOnlyDownloads = false;
  bool _convertAudioToMp3 = false;

  ThemeMode get themeMode => _themeMode;
  Locale? get locale => _locale;
  bool get autoSaveGallery => _autoSaveGallery;
  bool get autoPasteClipboard => _autoPasteClipboard;
  String get preferredQuality => _preferredQuality;
  int get cacheSizeBytes => _cacheSizeBytes;
  bool get allowExternalServices => _allowExternalServices;
  bool get removeCacheAfterGallery => _removeCacheAfterGallery;
  int get maxConcurrentDownloads => _maxConcurrentDownloads;
  bool get wifiOnlyDownloads => _wifiOnlyDownloads;
  bool get convertAudioToMp3 => _convertAudioToMp3;
  DownloadOptions get downloadOptions => DownloadOptions(
    autoSaveToGallery: autoSaveGallery,
    removeCacheAfterGallery: removeCacheAfterGallery,
  );
  late final Future<void> initialized;

  SettingsProvider({
    ExtractionPolicy? extractionPolicy,
    Future<int> Function()? measureLocalCopies,
  }) : _extractionPolicy = extractionPolicy ?? ExtractionPolicy(),
       _measureLocalCopies =
           measureLocalCopies ?? StorageService().calculateCacheSize {
    initialized = _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final themeStr = prefs.getString(AppConstants.keyThemeMode);
    if (themeStr == 'dark') {
      _themeMode = ThemeMode.dark;
    } else if (themeStr == 'light') {
      _themeMode = ThemeMode.light;
    } else {
      _themeMode = ThemeMode.system;
    }

    _autoSaveGallery = prefs.getBool(AppConstants.keyAutoSaveGallery) ?? true;
    _autoPasteClipboard =
        prefs.getBool(AppConstants.keyAutoPasteClipboard) ?? true;
    _preferredQuality =
        prefs.getString(AppConstants.keyPreferredQuality) ?? 'Highest';
    _allowExternalServices =
        prefs.getBool(AppConstants.keyAllowExternalServices) ?? true;
    _extractionPolicy.setAllowExternalServices(_allowExternalServices);
    _removeCacheAfterGallery =
        prefs.getBool(AppConstants.keyRemoveCacheAfterGallery) ?? true;
    _maxConcurrentDownloads =
        (prefs.getInt(AppConstants.keyMaxConcurrentDownloads) ?? 3)
            .clamp(1, 5)
            .toInt();
    _wifiOnlyDownloads =
        prefs.getBool(AppConstants.keyWifiOnlyDownloads) ?? false;
    _convertAudioToMp3 =
        prefs.getBool(AppConstants.keyConvertAudioToMp3) ?? false;
    final languageCode = prefs.getString(AppConstants.keyLanguageCode);
    _locale = languageCode == null ? null : Locale(languageCode);

    await refreshCacheSize();
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final themeStr = mode == ThemeMode.dark
        ? 'dark'
        : mode == ThemeMode.light
        ? 'light'
        : 'system';
    await prefs.setString(AppConstants.keyThemeMode, themeStr);
  }

  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(AppConstants.keyLanguageCode);
    } else {
      await prefs.setString(AppConstants.keyLanguageCode, locale.languageCode);
    }
  }

  Future<void> setAutoSaveGallery(bool value) async {
    _autoSaveGallery = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyAutoSaveGallery, value);
  }

  Future<void> setAutoPasteClipboard(bool value) async {
    _autoPasteClipboard = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyAutoPasteClipboard, value);
  }

  Future<void> setPreferredQuality(String quality) async {
    _preferredQuality = quality;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyPreferredQuality, quality);
  }

  Future<void> setAllowExternalServices(bool value) async {
    _allowExternalServices = value;
    _extractionPolicy.setAllowExternalServices(value);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyAllowExternalServices, value);
  }

  Future<void> setRemoveCacheAfterGallery(bool value) async {
    _removeCacheAfterGallery = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyRemoveCacheAfterGallery, value);
  }

  Future<void> setMaxConcurrentDownloads(int value) async {
    _maxConcurrentDownloads = value.clamp(1, 5).toInt();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      AppConstants.keyMaxConcurrentDownloads,
      _maxConcurrentDownloads,
    );
  }

  Future<void> setConvertAudioToMp3(bool value) async {
    _convertAudioToMp3 = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyConvertAudioToMp3, value);
  }

  Future<void> setWifiOnlyDownloads(bool value) async {
    _wifiOnlyDownloads = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyWifiOnlyDownloads, value);
  }

  Future<void>? _measuring;
  bool _measureAgain = false;

  /// Measures the files NimbleClip keeps in its own folder again.
  ///
  /// Asked for when Settings comes on screen and when a download leaves or
  /// removes a file, so several can arrive while one walk is running. They
  /// share that walk plus one more, which sees every change made meanwhile;
  /// separate walks could finish out of order and leave an older size up.
  Future<void> refreshCacheSize() {
    final running = _measuring;
    if (running != null) {
      _measureAgain = true;
      return running;
    }
    return _measuring = _measureUntilSettled();
  }

  Future<void> _measureUntilSettled() async {
    final before = _cacheSizeBytes;
    try {
      do {
        _measureAgain = false;
        try {
          _cacheSizeBytes = await _measureLocalCopies();
        } catch (_) {
          // An unreadable folder is no reason to lose the last good figure.
        }
      } while (_measureAgain);
    } finally {
      _measuring = null;
    }
    // The whole app listens here; a size that did not move rebuilds nothing.
    if (_cacheSizeBytes != before) notifyListeners();
  }
}
