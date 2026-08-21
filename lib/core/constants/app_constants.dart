class AppConstants {
  static const String appName = 'NimbleClip';
  static const String appTagline = 'Fast HD Video & Audio Downloader';
  static const String appRepoUrl = 'https://github.com/vannt-dev/nimbleclip';

  // Storage keys
  static const String keyThemeMode = 'theme_mode';
  static const String keyAutoSaveGallery = 'auto_save_gallery';
  static const String keyAutoPasteClipboard = 'auto_paste_clipboard';
  static const String keyPreferredQuality = 'preferred_quality';
  static const String keyLanguageCode = 'language_code';
  static const String keyDownloadHistory = 'download_history_list';

  // Network timeouts
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 60);

  // User Agents
  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';
  static const String mobileUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
}
