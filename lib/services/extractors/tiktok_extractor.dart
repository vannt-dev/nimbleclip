import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/utils/cors_helper.dart';
import '../../models/video_metadata.dart';
import '../../models/video_platform.dart';
import 'base_extractor.dart';

class TikTokExtractor implements BaseVideoExtractor {
  @override
  VideoPlatform get platform => VideoPlatform.tiktok;

  @override
  bool canHandle(String url) {
    final lower = url.toLowerCase();
    return lower.contains('tiktok.com') || lower.contains('douyin.com');
  }

  @override
  Future<VideoMetadata> extract(String url) async {
    try {
      // Primary API: TikWM (high reliability, no watermark, fast HD stream)
      final apiUrl = Uri.parse(CorsHelper.wrap('https://www.tikwm.com/api/'));
      final response = await http.post(
        apiUrl,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
          'Accept': 'application/json',
        },
        body: {'url': url, 'count': '12', 'cursor': '0', 'web': '1', 'hd': '1'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['code'] == 0 && json['data'] != null) {
          final data = json['data'] as Map<String, dynamic>;
          final id = data['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
          final title = data['title']?.toString().trim().isNotEmpty == true
              ? data['title'].toString()
              : 'TikTok Video ($id)';
          final authorData = data['author'] as Map<String, dynamic>? ?? {};
          final authorName = authorData['nickname']?.toString() ??
              authorData['unique_id']?.toString() ??
              'TikTok Creator';
          final authorAvatar = authorData['avatar']?.toString();
          final coverUrl = data['origin_cover']?.toString() ??
              data['cover']?.toString() ??
              '';
          final durationSec = data['duration'] as int?;

          final List<VideoQualityOption> qualities = [];

          // 1. HD No Watermark
          final hdPlay = data['hdplay']?.toString();
          if (hdPlay != null && hdPlay.isNotEmpty) {
            qualities.add(
              VideoQualityOption(
                id: 'tt_hd_$id',
                label: 'HD No Watermark (1080p)',
                quality: 'HD 1080p',
                format: 'mp4',
                downloadUrl: hdPlay.startsWith('http') ? hdPlay : 'https://www.tikwm.com$hdPlay',
                sizeBytes: data['hd_size'] as int?,
                isAudioOnly: false,
              ),
            );
          }

          // 2. Standard No Watermark
          final play = data['play']?.toString();
          if (play != null && play.isNotEmpty) {
            qualities.add(
              VideoQualityOption(
                id: 'tt_sd_$id',
                label: 'Standard No Watermark (720p)',
                quality: 'SD 720p',
                format: 'mp4',
                downloadUrl: play.startsWith('http') ? play : 'https://www.tikwm.com$play',
                sizeBytes: data['size'] as int?,
                isAudioOnly: false,
              ),
            );
          }

          // 3. Audio / Original Sound MP3
          final music = data['music']?.toString();
          if (music != null && music.isNotEmpty) {
            final musicInfo = data['music_info'] as Map<String, dynamic>? ?? {};
            final musicTitle = musicInfo['title']?.toString() ?? 'Original Sound';
            qualities.add(
              VideoQualityOption(
                id: 'tt_audio_$id',
                label: 'Audio MP3 ($musicTitle)',
                quality: 'Audio MP3',
                format: 'mp3',
                downloadUrl: music.startsWith('http') ? music : 'https://www.tikwm.com$music',
                isAudioOnly: true,
              ),
            );
          }

          // If no video was added, check watermark play
          if (qualities.isEmpty) {
            final wmPlay = data['wmplay']?.toString();
            if (wmPlay != null && wmPlay.isNotEmpty) {
              qualities.add(
                VideoQualityOption(
                  id: 'tt_wm_$id',
                  label: 'Original Video',
                  quality: 'Standard',
                  format: 'mp4',
                  downloadUrl: wmPlay.startsWith('http') ? wmPlay : 'https://www.tikwm.com$wmPlay',
                  isAudioOnly: false,
                ),
              );
            }
          }

          return VideoMetadata(
            id: id,
            originalUrl: url,
            title: title,
            description: title,
            author: authorName,
            authorAvatar: authorAvatar,
            coverUrl: coverUrl,
            duration: durationSec != null ? Duration(seconds: durationSec) : null,
            platform: VideoPlatform.tiktok,
            qualities: qualities,
            viewCount: data['play_count'] as int?,
            likeCount: data['digg_count'] as int?,
            commentCount: data['comment_count'] as int?,
            shareCount: data['share_count'] as int?,
          );
        }
      }

      throw Exception('Could not parse TikTok response: ${response.body}');
    } catch (e) {
      throw Exception('Failed to extract TikTok video: $e');
    }
  }
}
