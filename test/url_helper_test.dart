import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/core/utils/url_helper.dart';
import 'package:nimble_clip/models/video_platform.dart';

void main() {
  group('UrlHelper.detectPlatform', () {
    test('detects YouTube in every link shape', () {
      for (final url in const [
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtu.be/dQw4w9WgXcQ',
        'https://youtube.com/shorts/abc123xyz',
        'https://m.youtube.com/watch?v=abc',
        'https://www.youtube-nocookie.com/embed/abc',
      ]) {
        expect(
          UrlHelper.detectPlatform(url),
          VideoPlatform.youtube,
          reason: url,
        );
      }
    });

    test('detects TikTok including short hosts', () {
      for (final url in const [
        'https://www.tiktok.com/@user/video/1234567890',
        'https://vm.tiktok.com/ZMxxxx/',
        'https://vt.tiktok.com/ZSabc/',
      ]) {
        expect(
          UrlHelper.detectPlatform(url),
          VideoPlatform.tiktok,
          reason: url,
        );
      }
    });

    test('detects Facebook, X and Instagram', () {
      expect(
        UrlHelper.detectPlatform('https://www.facebook.com/watch?v=123'),
        VideoPlatform.facebook,
      );
      expect(
        UrlHelper.detectPlatform('https://fb.watch/abcdef/'),
        VideoPlatform.facebook,
      );
      expect(
        UrlHelper.detectPlatform('https://x.com/u/status/1'),
        VideoPlatform.twitter,
      );
      expect(
        UrlHelper.detectPlatform('https://twitter.com/u/status/1'),
        VideoPlatform.twitter,
      );
      expect(
        UrlHelper.detectPlatform('https://t.co/abc123'),
        VideoPlatform.twitter,
      );
      expect(
        UrlHelper.detectPlatform('https://www.instagram.com/reel/Cxyz/'),
        VideoPlatform.instagram,
      );
    });

    test('matches on the host, not anywhere in the URL', () {
      // A platform name in the query string must not hijack routing.
      expect(
        UrlHelper.detectPlatform('https://evil.example.com/?next=youtube.com'),
        VideoPlatform.generic,
      );
      expect(
        UrlHelper.detectPlatform('https://nottiktok.com/video/1'),
        VideoPlatform.generic,
      );
      expect(
        UrlHelper.detectPlatform('https://cdn.example.org/clip.mp4'),
        VideoPlatform.generic,
      );
    });
  });

  group('UrlHelper.extractCleanUrl', () {
    test('pulls the link out of shared text', () {
      expect(
        UrlHelper.extractCleanUrl(
          'Check out this awesome video https://youtu.be/dQw4w9WgXcQ from YouTube!',
        ),
        'https://youtu.be/dQw4w9WgXcQ',
      );
    });

    test('drops trailing sentence punctuation', () {
      expect(
        UrlHelper.extractCleanUrl('Xem clip này https://youtu.be/abcdefghijk.'),
        'https://youtu.be/abcdefghijk',
      );
    });

    test('returns empty for empty input', () {
      expect(UrlHelper.extractCleanUrl(''), '');
    });
  });

  group('UrlHelper.extractUrls', () {
    test('extracts, cleans and de-duplicates multiple shared links', () {
      expect(
        UrlHelper.extractUrls(
          'Một https://youtu.be/abcdefghijk. Hai https://facebook.com/reel/123! Lặp https://youtu.be/abcdefghijk',
        ),
        ['https://youtu.be/abcdefghijk', 'https://facebook.com/reel/123'],
      );
    });

    test('ignores invalid text and non-http schemes', () {
      expect(UrlHelper.extractUrls('hello ftp://example.com/a.mp4'), isEmpty);
    });
  });

  group('UrlHelper.isValidVideoUrl', () {
    test('accepts http and https with a host', () {
      expect(UrlHelper.isValidVideoUrl('https://example.com/a.mp4'), isTrue);
      expect(UrlHelper.isValidVideoUrl('http://example.com'), isTrue);
    });

    test('rejects other schemes, bare text and hostless URLs', () {
      expect(UrlHelper.isValidVideoUrl(''), isFalse);
      expect(UrlHelper.isValidVideoUrl('not a url'), isFalse);
      expect(UrlHelper.isValidVideoUrl('ftp://example.com/a.mp4'), isFalse);
      expect(UrlHelper.isValidVideoUrl('file:///etc/passwd'), isFalse);
      expect(UrlHelper.isValidVideoUrl('https:///nohost'), isFalse);
    });
  });

  group('UrlHelper.isShortLink', () {
    test('flags links whose destination needs a redirect', () {
      expect(UrlHelper.isShortLink('https://t.co/abc'), isTrue);
      expect(UrlHelper.isShortLink('https://fb.watch/abc/'), isTrue);
      expect(
        UrlHelper.isShortLink('https://www.facebook.com/share/r/1DoJYK37gr/'),
        isTrue,
      );
      expect(
        UrlHelper.isShortLink('https://m.facebook.com/share/v/AbCd123'),
        isTrue,
      );
      expect(
        UrlHelper.isShortLink('https://facebook.com/share/p/Post123/?x=1'),
        isTrue,
      );
      expect(UrlHelper.isShortLink('https://vm.tiktok.com/ZM1/'), isTrue);
      expect(
        UrlHelper.isShortLink('https://www.tiktok.com/@u/video/1'),
        isFalse,
      );
      expect(
        UrlHelper.isShortLink('https://www.facebook.com/reel/123456'),
        isFalse,
      );
      for (final path in [
        '/share/r/ReelToken/',
        '/share/v/VideoToken',
        '/share/p/PostToken/?mibextid=test',
      ]) {
        expect(
          UrlHelper.isShortLink('https://web.facebook.com$path'),
          isTrue,
          reason: path,
        );
      }
      expect(
        UrlHelper.isShortLink('https://example.com/share/r/ReelToken/'),
        isFalse,
      );
    });
  });
}
