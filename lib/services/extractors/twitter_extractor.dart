import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/video_metadata.dart';
import '../../models/video_platform.dart';
import 'base_extractor.dart';

class TwitterExtractor implements BaseVideoExtractor {
  @override
  VideoPlatform get platform => VideoPlatform.twitter;

  @override
  bool canHandle(String url) {
    final lower = url.toLowerCase();
    return lower.contains('twitter.com') ||
        lower.contains('x.com') ||
        lower.contains('t.co');
  }

  String? _extractTweetId(String url) {
    final regex = RegExp(r'status(?:es)?\/(\d+)');
    final match = regex.firstMatch(url);
    return match?.group(1);
  }

  @override
  Future<VideoMetadata> extract(String url) async {
    final tweetId = _extractTweetId(url);
    if (tweetId == null) {
      throw Exception('Could not extract Tweet / X ID from URL: $url');
    }

    try {
      // 1. Try FxTwitter API
      final fxUrl = Uri.parse('https://api.fxtwitter.com/status/$tweetId');
      final response = await http.get(
        fxUrl,
        headers: {'User-Agent': 'SnapVideo/1.0', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['code'] == 200 && json['tweet'] != null) {
          final tweet = json['tweet'] as Map<String, dynamic>;
          final media = tweet['media'] as Map<String, dynamic>?;
          final videos = media?['videos'] as List<dynamic>?;

          if (videos != null && videos.isNotEmpty) {
            final firstVideo = videos.first as Map<String, dynamic>;
            final variants = firstVideo['variants'] as List<dynamic>? ?? [];

            final List<VideoQualityOption> qualities = [];

            // Sort variants by bitrate descending
            final mp4Variants = variants
                .where((v) => (v['content_type'] ?? '').toString().contains('mp4'))
                .toList();

            mp4Variants.sort((a, b) {
              final bBitrate = (b['bitrate'] as int?) ?? 0;
              final aBitrate = (a['bitrate'] as int?) ?? 0;
              return bBitrate.compareTo(aBitrate);
            });

            for (var i = 0; i < mp4Variants.length; i++) {
              final v = mp4Variants[i];
              final bitrate = (v['bitrate'] as int?) ?? 0;
              final bitrateKbps = (bitrate / 1000).round();
              final qualityName = bitrateKbps > 1500
                  ? '1080p HD'
                  : bitrateKbps > 800
                      ? '720p HD'
                      : bitrateKbps > 400
                          ? '480p SD'
                          : '360p SD';

              qualities.add(
                VideoQualityOption(
                  id: 'x_${tweetId}_$i',
                  label: '$qualityName ($bitrateKbps kbps)',
                  quality: qualityName,
                  format: 'mp4',
                  downloadUrl: v['url'].toString(),
                  isAudioOnly: false,
                ),
              );
            }

            // Fallback if no variants found but video url exists
            if (qualities.isEmpty && firstVideo['url'] != null) {
              qualities.add(
                VideoQualityOption(
                  id: 'x_${tweetId}_def',
                  label: 'Standard Quality MP4',
                  quality: 'HD',
                  format: 'mp4',
                  downloadUrl: firstVideo['url'].toString(),
                  isAudioOnly: false,
                ),
              );
            }

            final author = tweet['author'] as Map<String, dynamic>? ?? {};
            final authorName = author['name']?.toString() ??
                author['screen_name']?.toString() ??
                'X User';
            final authorAvatar = author['avatar_url']?.toString();
            final title = tweet['text']?.toString().trim().isNotEmpty == true
                ? tweet['text'].toString()
                : 'X Post by @${author['screen_name']}';
            final coverUrl = firstVideo['thumbnail_url']?.toString() ?? '';
            final durationSec = (firstVideo['duration'] as num?)?.toInt();

            return VideoMetadata(
              id: tweetId,
              originalUrl: url,
              title: title,
              description: tweet['text']?.toString(),
              author: authorName,
              authorAvatar: authorAvatar,
              coverUrl: coverUrl,
              duration: durationSec != null ? Duration(seconds: durationSec) : null,
              platform: VideoPlatform.twitter,
              qualities: qualities,
              viewCount: tweet['views'] as int?,
              likeCount: tweet['likes'] as int?,
              commentCount: tweet['replies'] as int?,
              shareCount: tweet['retweets'] as int?,
            );
          }
        }
      }

      // 2. Fallback: VxTwitter API
      final vxUrl = Uri.parse('https://api.vxtwitter.com/Twitter/status/$tweetId');
      final vxResponse = await http.get(vxUrl).timeout(const Duration(seconds: 10));
      if (vxResponse.statusCode == 200) {
        final vxJson = jsonDecode(vxResponse.body) as Map<String, dynamic>;
        final mediaUrls = vxJson['mediaURLs'] as List<dynamic>? ?? [];
        final videoUrls = mediaUrls.where((u) => u.toString().endsWith('.mp4')).toList();

        if (videoUrls.isNotEmpty) {
          final downloadUrl = videoUrls.first.toString();
          return VideoMetadata(
            id: tweetId,
            originalUrl: url,
            title: vxJson['text']?.toString() ?? 'X Video ($tweetId)',
            description: vxJson['text']?.toString(),
            author: vxJson['user_name']?.toString() ?? 'X User',
            authorAvatar: null,
            coverUrl: '',
            duration: null,
            platform: VideoPlatform.twitter,
            qualities: [
              VideoQualityOption(
                id: 'vx_$tweetId',
                label: 'High Quality MP4',
                quality: 'HD',
                format: 'mp4',
                downloadUrl: downloadUrl,
                isAudioOnly: false,
              ),
            ],
            viewCount: null,
            likeCount: vxJson['likes'] as int?,
            commentCount: vxJson['replies'] as int?,
            shareCount: vxJson['retweets'] as int?,
          );
        }
      }

      throw Exception('No downloadable video found for this tweet.');
    } catch (e) {
      throw Exception('Failed to extract Twitter / X video: $e');
    }
  }
}
