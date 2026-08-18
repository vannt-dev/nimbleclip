import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/utils/cors_helper.dart';
import '../../models/video_metadata.dart';
import '../../models/video_platform.dart';
import 'base_extractor.dart';

class FacebookExtractor implements BaseVideoExtractor {
  @override
  VideoPlatform get platform => VideoPlatform.facebook;

  @override
  bool canHandle(String url) {
    final lower = url.toLowerCase();
    return lower.contains('facebook.com') ||
        lower.contains('fb.watch') ||
        lower.contains('fb.com');
  }

  String _cleanEscapedString(String str) {
    return str
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u0026', '&')
        .replaceAll(r'\u003C', '<')
        .replaceAll(r'\u003E', '>')
        .replaceAll(r'\u0022', '"')
        .replaceAll(r'\', '');
  }

  @override
  Future<VideoMetadata> extract(String url) async {
    final cleanUrl = url.trim();

    try {
      // 1. First strategy: Direct HTML scraping with Android / iOS User-Agent
      final response = await http.get(
        Uri.parse(CorsHelper.wrap(cleanUrl)),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
          'sec-fetch-dest': 'document',
          'sec-fetch-mode': 'navigate',
          'sec-fetch-site': 'none',
        },
      ).timeout(const Duration(seconds: 15));

      final html = response.body;
      final List<VideoQualityOption> qualities = [];

      // Extract HD url
      final hdPatterns = [
        RegExp(r'"browser_native_hd_url":"([^"]+)"'),
        RegExp(r'"hd_src_no_ratelimit":"([^"]+)"'),
        RegExp(r'"hd_src":"([^"]+)"'),
        RegExp(r'"playable_url_quality_hd":"([^"]+)"'),
      ];

      String? hdUrl;
      for (final p in hdPatterns) {
        final match = p.firstMatch(html);
        if (match != null && match.group(1) != null) {
          hdUrl = _cleanEscapedString(match.group(1)!);
          break;
        }
      }

      // Extract SD url
      final sdPatterns = [
        RegExp(r'"browser_native_sd_url":"([^"]+)"'),
        RegExp(r'"sd_src_no_ratelimit":"([^"]+)"'),
        RegExp(r'"sd_src":"([^"]+)"'),
        RegExp(r'"playable_url":"([^"]+)"'),
      ];

      String? sdUrl;
      for (final p in sdPatterns) {
        final match = p.firstMatch(html);
        if (match != null && match.group(1) != null) {
          sdUrl = _cleanEscapedString(match.group(1)!);
          break;
        }
      }

      // Title & Thumbnail extraction
      final titleMatch = RegExp(r'<title>(.*?)<\/title>', caseSensitive: false).firstMatch(html);
      String title = titleMatch?.group(1) ?? 'Facebook Video';
      if (title.contains('| Facebook')) {
        title = title.replaceAll('| Facebook', '').trim();
      }

      final thumbMatch = RegExp(r'"preferred_thumbnail":\{"image":\{"uri":"([^"]+)"\}').firstMatch(html) ??
          RegExp(r'property="og:image"\s+content="([^"]+)"').firstMatch(html);
      final coverUrl = thumbMatch != null && thumbMatch.group(1) != null
          ? _cleanEscapedString(thumbMatch.group(1)!)
          : '';

      final id = DateTime.now().millisecondsSinceEpoch.toString();

      if (hdUrl != null && hdUrl.isNotEmpty) {
        qualities.add(
          VideoQualityOption(
            id: 'fb_hd_$id',
            label: 'HD Quality (720p/1080p)',
            quality: 'HD',
            format: 'mp4',
            downloadUrl: hdUrl,
            isAudioOnly: false,
          ),
        );
      }

      if (sdUrl != null && sdUrl.isNotEmpty) {
        qualities.add(
          VideoQualityOption(
            id: 'fb_sd_$id',
            label: 'SD Quality (Standard)',
            quality: 'SD',
            format: 'mp4',
            downloadUrl: sdUrl,
            isAudioOnly: false,
          ),
        );
      }

      if (qualities.isNotEmpty) {
        return VideoMetadata(
          id: id,
          originalUrl: cleanUrl,
          title: title.isNotEmpty ? title : 'Facebook Video',
          description: title,
          author: 'Facebook User',
          authorAvatar: null,
          coverUrl: coverUrl,
          duration: null,
          platform: VideoPlatform.facebook,
          qualities: qualities,
          viewCount: null,
          likeCount: null,
          commentCount: null,
          shareCount: null,
        );
      }

      // 2. Second strategy: Fallback to Universal Rapid Web Extractor API
      final fallbackApi = Uri.parse(CorsHelper.wrap('https://api.cobalt.tools/api/json'));
      final apiRes = await http.post(
        fallbackApi,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'User-Agent': 'SnapVideo/1.0',
        },
        body: jsonEncode({'url': cleanUrl}),
      ).timeout(const Duration(seconds: 10));

      if (apiRes.statusCode == 200) {
        final apiJson = jsonDecode(apiRes.body) as Map<String, dynamic>;
        final directUrl = apiJson['url']?.toString();
        if (directUrl != null && directUrl.isNotEmpty) {
          return VideoMetadata(
            id: id,
            originalUrl: cleanUrl,
            title: title.isNotEmpty ? title : 'Facebook Video',
            description: null,
            author: 'Facebook',
            authorAvatar: null,
            coverUrl: coverUrl,
            duration: null,
            platform: VideoPlatform.facebook,
            qualities: [
              VideoQualityOption(
                id: 'fb_api_$id',
                label: 'High Quality MP4',
                quality: 'HD',
                format: 'mp4',
                downloadUrl: directUrl,
                isAudioOnly: false,
              ),
            ],
            viewCount: null,
            likeCount: null,
            commentCount: null,
            shareCount: null,
          );
        }
      }

      throw Exception(
        'Could not extract video from Facebook link. Please make sure the video is public.',
      );
    } catch (e) {
      throw Exception('Facebook extraction failed: $e');
    }
  }
}
