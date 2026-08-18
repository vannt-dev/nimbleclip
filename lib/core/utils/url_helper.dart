import '../../models/video_platform.dart';

class UrlHelper {
  static String extractCleanUrl(String text) {
    if (text.isEmpty) return '';
    
    // Find http/https link inside potentially long shared text
    final urlRegex = RegExp(r'https?://[^\s<>"]+');
    final match = urlRegex.firstMatch(text);
    if (match != null) {
      String url = match.group(0) ?? '';
      return url.trim();
    }
    return text.trim();
  }

  static VideoPlatform detectPlatform(String url) {
    final lower = url.toLowerCase();
    
    if (lower.contains('youtube.com') ||
        lower.contains('youtu.be') ||
        lower.contains('youtube.com/shorts')) {
      return VideoPlatform.youtube;
    }
    if (lower.contains('tiktok.com') ||
        lower.contains('douyin.com')) {
      return VideoPlatform.tiktok;
    }
    if (lower.contains('facebook.com') ||
        lower.contains('fb.watch') ||
        lower.contains('fb.com')) {
      return VideoPlatform.facebook;
    }
    if (lower.contains('twitter.com') ||
        lower.contains('x.com') ||
        lower.contains('t.co')) {
      return VideoPlatform.twitter;
    }
    if (lower.contains('instagram.com')) {
      return VideoPlatform.instagram;
    }
    return VideoPlatform.generic;
  }

  static bool isValidVideoUrl(String url) {
    if (url.isEmpty) return false;
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (_) {
      return false;
    }
  }
}
