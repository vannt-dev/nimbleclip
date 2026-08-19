import 'dart:convert';

import '../../core/constants/app_constants.dart';
import '../../core/utils/http_helper.dart';
import '../../core/utils/quality_helper.dart';
import '../../models/video_metadata.dart';
import '../../models/video_platform.dart';
import 'base_extractor.dart';

class TikTokExtractor extends BaseVideoExtractor {
  const TikTokExtractor();

  static const String _apiBase = 'https://www.tikwm.com';

  @override
  VideoPlatform get platform => VideoPlatform.tiktok;

  /// TikWM returns CDN paths relative to its own host for some fields.
  String _absolute(String path) =>
      path.startsWith('http') ? path : '$_apiBase$path';

  @override
  Future<VideoMetadata> extract(String url) async {
    final Map<String, dynamic> json;
    try {
      final response = await ExtractorHttp.post(
        '$_apiBase/api/',
        userAgent: AppConstants.mobileUserAgent,
        headers: {'Accept': 'application/json'},
        body: {'url': url, 'count': '12', 'cursor': '0', 'web': '1', 'hd': '1'},
      );
      if (response.statusCode != 200) {
        throw ExtractionException(
          'Dịch vụ TikTok trả về mã ${response.statusCode}. Hãy thử lại sau ít phút.',
        );
      }
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } on ExtractionException {
      rethrow;
    } catch (e) {
      throw ExtractionException('Không kết nối được dịch vụ TikTok: $e');
    }

    if (json['code'] != 0 || json['data'] == null) {
      final message = json['msg']?.toString();
      throw ExtractionException(
        message != null && message.isNotEmpty
            ? 'TikTok: $message'
            : 'Không đọc được dữ liệu video TikTok. Link có thể đã bị xoá hoặc ở chế độ riêng tư.',
      );
    }

    final data = json['data'] as Map<String, dynamic>;
    final id = data['id']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();
    final author = data['author'] as Map<String, dynamic>? ?? {};
    final qualities = <VideoQualityOption>[];

    final hdPlay = data['hdplay']?.toString();
    if (hdPlay != null && hdPlay.isNotEmpty) {
      qualities.add(
        VideoQualityOption(
          id: 'tt_hd_$id',
          label: 'HD 1080p (Không logo)',
          quality: 'HD 1080p',
          format: 'mp4',
          downloadUrl: _absolute(hdPlay),
          sizeBytes: (data['hd_size'] as num?)?.toInt(),
        ),
      );
    }

    final play = data['play']?.toString();
    if (play != null && play.isNotEmpty) {
      qualities.add(
        VideoQualityOption(
          id: 'tt_sd_$id',
          label: '720p (Không logo)',
          quality: '720p',
          format: 'mp4',
          downloadUrl: _absolute(play),
          sizeBytes: (data['size'] as num?)?.toInt(),
        ),
      );
    }

    final wmPlay = data['wmplay']?.toString();
    if (qualities.isEmpty && wmPlay != null && wmPlay.isNotEmpty) {
      qualities.add(
        VideoQualityOption(
          id: 'tt_wm_$id',
          label: '720p (Có logo TikTok)',
          quality: '720p',
          format: 'mp4',
          downloadUrl: _absolute(wmPlay),
          sizeBytes: (data['wm_size'] as num?)?.toInt(),
        ),
      );
    }

    final music = data['music']?.toString();
    if (music != null && music.isNotEmpty) {
      final musicInfo = data['music_info'] as Map<String, dynamic>? ?? {};
      final musicTitle = musicInfo['title']?.toString() ?? 'Nhạc gốc';
      qualities.add(
        VideoQualityOption(
          id: 'tt_audio_$id',
          label: 'Âm thanh MP3 ($musicTitle)',
          quality: 'Audio MP3',
          format: 'mp3',
          downloadUrl: _absolute(music),
          isAudioOnly: true,
        ),
      );
    }

    if (qualities.isEmpty) {
      throw const ExtractionException(
        'TikTok không trả về luồng tải nào cho video này.',
      );
    }

    final title = data['title']?.toString().trim();
    final durationSec = (data['duration'] as num?)?.toInt();

    return VideoMetadata(
      id: id,
      originalUrl: url,
      title: title != null && title.isNotEmpty ? title : 'TikTok Video ($id)',
      description: title,
      author: author['nickname']?.toString() ??
          author['unique_id']?.toString() ??
          'TikTok Creator',
      authorAvatar: author['avatar']?.toString(),
      coverUrl: data['origin_cover']?.toString() ??
          data['cover']?.toString() ??
          '',
      duration: durationSec != null && durationSec > 0
          ? Duration(seconds: durationSec)
          : null,
      platform: VideoPlatform.tiktok,
      qualities: QualityHelper.sortedByQuality(qualities),
      viewCount: (data['play_count'] as num?)?.toInt(),
      likeCount: (data['digg_count'] as num?)?.toInt(),
      commentCount: (data['comment_count'] as num?)?.toInt(),
      shareCount: (data['share_count'] as num?)?.toInt(),
    );
  }
}
