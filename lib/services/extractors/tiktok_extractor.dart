import 'dart:convert';

import '../../core/constants/app_constants.dart';
import '../../core/utils/http_helper.dart';
import '../../core/utils/media_format_helper.dart';
import '../../core/utils/external_service_policy.dart';
import '../../core/utils/quality_helper.dart';
import '../../models/quality_descriptor.dart';
import '../../models/video_metadata.dart';
import '../../models/video_platform.dart';
import 'base_extractor.dart';
import 'extraction_failure.dart';

class TikTokExtractor extends BaseVideoExtractor {
  final ExternalServiceAccess externalServiceAccess;

  const TikTokExtractor({ExternalServiceAccess? externalServiceAccess})
    : externalServiceAccess =
          externalServiceAccess ?? const FixedExternalServiceAccess(true);

  static const String _apiBase = 'https://www.tikwm.com';

  @override
  VideoPlatform get platform => VideoPlatform.tiktok;

  /// TikWM returns CDN paths relative to its own host for some fields.
  String _absolute(String path) =>
      path.startsWith('http') ? path : '$_apiBase$path';

  @override
  Future<VideoMetadata> extract(String url) async {
    if (!externalServiceAccess.allowExternalServices) {
      throw ExtractionException(
        const ExtractionFailure(ExtractionFailureKind.externalServicesDisabled),
      );
    }
    final Map<String, dynamic> json;
    try {
      final response = await ExtractorHttp.postWithRetry(
        '$_apiBase/api/',
        service: 'TikWM',
        userAgent: AppConstants.mobileUserAgent,
        headers: {'Accept': 'application/json'},
        body: {'url': url, 'count': '12', 'cursor': '0', 'web': '1', 'hd': '1'},
      );
      if (response.statusCode != 200) {
        throw ExtractionException(
          ExtractionFailure(
            ExtractionFailureKind.tiktokServiceStatus,
            detail: '${response.statusCode}',
          ),
        );
      }
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } on ExtractionException {
      rethrow;
    } catch (e) {
      throw ExtractionException(
        ExtractionFailure(
          ExtractionFailureKind.tiktokConnectionFailed,
          detail: e.toString(),
        ),
      );
    }

    if (json['code'] != 0 || json['data'] == null) {
      final message = json['msg']?.toString();
      // The `TikTok: ` prefix now lives in `describeExtractionFailure`, so the
      // server's own wording still reaches the user unchanged.
      throw ExtractionException(
        ExtractionFailure(
          ExtractionFailureKind.tiktokInvalidData,
          detail: message,
        ),
      );
    }

    final data = json['data'] as Map<String, dynamic>;
    final id =
        data['id']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();
    final author = data['author'] as Map<String, dynamic>? ?? {};
    final qualities = <VideoQualityOption>[];

    final images = data['images'] as List<dynamic>? ?? const [];
    for (var index = 0; index < images.length; index++) {
      final imageUrl = images[index]?.toString() ?? '';
      if (imageUrl.isEmpty) continue;
      qualities.add(
        VideoQualityOption.image(
          id: 'tt_image_${index + 1}_$id',
          mediaId: 'tt_image_${index + 1}_$id',
          label: ImageIndex(index + 1),
          format: MediaFormatHelper.inferImageFormat(imageUrl),
          downloadUrl: _absolute(imageUrl),
        ),
      );
    }

    final hdPlay = data['hdplay']?.toString();
    if (images.isEmpty && hdPlay != null && hdPlay.isNotEmpty) {
      qualities.add(
        VideoQualityOption.video(
          id: 'tt_hd_$id',
          mediaId: 'tt_video_$id',
          label: const WatermarkedVideo('HD 1080p', watermarked: false),
          quality: 'HD 1080p',
          format: 'mp4',
          downloadUrl: _absolute(hdPlay),
          sizeBytes: (data['hd_size'] as num?)?.toInt(),
        ),
      );
    }

    final play = data['play']?.toString();
    if (images.isEmpty && play != null && play.isNotEmpty) {
      qualities.add(
        VideoQualityOption.video(
          id: 'tt_sd_$id',
          mediaId: 'tt_video_$id',
          label: const WatermarkedVideo('720p', watermarked: false),
          quality: '720p',
          format: 'mp4',
          downloadUrl: _absolute(play),
          sizeBytes: (data['size'] as num?)?.toInt(),
        ),
      );
    }

    final wmPlay = data['wmplay']?.toString();
    if (images.isEmpty &&
        qualities.isEmpty &&
        wmPlay != null &&
        wmPlay.isNotEmpty) {
      qualities.add(
        VideoQualityOption.video(
          id: 'tt_wm_$id',
          mediaId: 'tt_video_$id',
          label: const WatermarkedVideo('720p', watermarked: true),
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
      final musicTitle = musicInfo['title']?.toString();
      qualities.add(
        VideoQualityOption.audio(
          id: 'tt_audio_$id',
          label: AudioMp3(musicTitle),
          quality: 'Audio MP3',
          format: 'mp3',
          downloadUrl: _absolute(music),
        ),
      );
    }

    if (qualities.isEmpty) {
      throw ExtractionException(
        const ExtractionFailure(ExtractionFailureKind.tiktokNoStreams),
      );
    }

    final title = data['title']?.toString().trim();
    final durationSec = (data['duration'] as num?)?.toInt();

    return VideoMetadata(
      id: id,
      originalUrl: url,
      title: title != null && title.isNotEmpty ? title : 'TikTok Video ($id)',
      description: title,
      author:
          author['nickname']?.toString() ??
          author['unique_id']?.toString() ??
          'TikTok Creator',
      authorAvatar: author['avatar']?.toString(),
      coverUrl:
          data['origin_cover']?.toString() ?? data['cover']?.toString() ?? '',
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
