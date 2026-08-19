import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_lib;

import '../../core/utils/http_helper.dart';
import '../../core/utils/json_scanner.dart';
import '../../core/utils/quality_helper.dart';
import '../../models/video_metadata.dart';
import '../../models/video_platform.dart';
import 'base_extractor.dart';

class YouTubeExtractor extends BaseVideoExtractor {
  const YouTubeExtractor({this.useNativeClient = true});

  final bool useNativeClient;

  @override
  VideoPlatform get platform => VideoPlatform.youtube;

  static final RegExp _videoIdPattern = RegExp(
    r'(?:youtu\.be/|youtube(?:-nocookie)?\.com/(?:embed/|v/|live/|shorts/|watch\?(?:.*&)?v=))([\w-]{11})',
  );

  String? _extractVideoId(String url) =>
      _videoIdPattern.firstMatch(url)?.group(1);

  @override
  Future<VideoMetadata> extract(String url) async {
    // Native platforms get the real deal: youtube_explode_dart deciphers
    // signature-protected stream URLs, which plain HTML scraping cannot.
    if (!kIsWeb && useNativeClient) {
      final native = await _extractNative(url);
      if (native != null) return native;
    }

    final videoId = _extractVideoId(url);
    if (videoId == null) {
      throw const ExtractionException(
        'Không tìm thấy Video ID hợp lệ trong link YouTube.',
      );
    }
    return _extractFromWatchPage(url, videoId);
  }

  Future<VideoMetadata?> _extractNative(String url) async {
    final yt = yt_lib.YoutubeExplode();
    try {
      final video = await yt.videos.get(url);
      final manifest = await yt.videos.streamsClient.getManifest(video.id);
      final qualities = <VideoQualityOption>[];

      for (final stream in manifest.muxed.sortByVideoQuality()) {
        qualities.add(
          VideoQualityOption(
            id: 'yt_muxed_${stream.tag}',
            label: '${stream.qualityLabel} (Video + Âm thanh)',
            quality: stream.qualityLabel,
            format: stream.container.name,
            downloadUrl: stream.url.toString(),
            sizeBytes: stream.size.totalBytes,
          ),
        );
      }

      final audioStreams = manifest.audioOnly.sortByBitrate();
      if (audioStreams.isNotEmpty) {
        final bestAudio = audioStreams.withHighestBitrate();
        final kbps = bestAudio.bitrate.kiloBitsPerSecond.round();
        qualities.add(
          VideoQualityOption(
            id: 'yt_audio_${bestAudio.tag}',
            label: 'Âm thanh M4A ($kbps kbps)',
            quality: 'Audio ($kbps kbps)',
            format: 'm4a',
            downloadUrl: bestAudio.url.toString(),
            sizeBytes: bestAudio.size.totalBytes,
            isAudioOnly: true,
          ),
        );
      }

      if (qualities.isEmpty) return null;

      return VideoMetadata(
        id: video.id.value,
        originalUrl: url,
        title: video.title,
        description: video.description,
        author: video.author,
        coverUrl: video.thumbnails.highResUrl.isNotEmpty
            ? video.thumbnails.highResUrl
            : video.thumbnails.mediumResUrl,
        duration: video.duration,
        platform: VideoPlatform.youtube,
        qualities: QualityHelper.sortedByQuality(qualities),
        viewCount: video.engagement.viewCount,
        likeCount: video.engagement.likeCount,
      );
    } catch (_) {
      // Fall through to the watch-page strategy.
      return null;
    } finally {
      yt.close();
    }
  }

  Future<VideoMetadata> _extractFromWatchPage(String url, String videoId) async {
    final http.Response response;
    try {
      response = await ExtractorHttp.get(
        'https://www.youtube.com/watch?v=$videoId',
      );
    } catch (e) {
      throw ExtractionException('Không tải được trang YouTube: $e');
    }

    // A balanced-brace scan, not a non-greedy regex: the player response
    // contains nested objects and strings that truncate `({.+?});` early.
    final blob =
        extractJsonAfterMarker(response.body, 'ytInitialPlayerResponse');
    if (blob == null) {
      throw const ExtractionException(
        'YouTube không trả về dữ liệu trình phát. Video có thể ở chế độ riêng tư '
        'hoặc bị giới hạn độ tuổi.',
      );
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(blob) as Map<String, dynamic>;
    } catch (e) {
      throw ExtractionException('Dữ liệu YouTube không hợp lệ: $e');
    }

    final playability = json['playabilityStatus'] as Map<String, dynamic>?;
    final status = playability?['status']?.toString();
    if (status != null && status != 'OK') {
      final reason = playability?['reason']?.toString() ?? status;
      throw ExtractionException('YouTube từ chối phát video này: $reason');
    }

    final details = json['videoDetails'] as Map<String, dynamic>? ?? {};
    final streamingData = json['streamingData'] as Map<String, dynamic>?;
    final qualities = <VideoQualityOption>[];
    var hasCipheredStreams = false;

    /// `signatureCipher` streams need YouTube's player JS to be deciphered,
    /// which only the native path can do — note them so the error message can
    /// say why nothing was found.
    String? usableUrl(Map<String, dynamic> format) {
      final directUrl = format['url']?.toString();
      if (directUrl != null && directUrl.isNotEmpty) return directUrl;
      if (format['signatureCipher'] != null) hasCipheredStreams = true;
      return null;
    }

    final muxed = streamingData?['formats'] as List<dynamic>? ?? [];
    for (var i = 0; i < muxed.length; i++) {
      final format = muxed[i] as Map<String, dynamic>;
      final directUrl = usableUrl(format);
      if (directUrl == null) continue;

      final mimeType = format['mimeType']?.toString() ?? 'video/mp4';
      final quality =
          format['qualityLabel']?.toString() ?? '${format['height'] ?? ''}p';
      qualities.add(
        VideoQualityOption(
          id: 'yt_video_${videoId}_$i',
          label: '$quality (Video + Âm thanh)',
          quality: quality,
          format: mimeType.contains('webm') ? 'webm' : 'mp4',
          downloadUrl: directUrl,
          sizeBytes: int.tryParse(format['contentLength']?.toString() ?? ''),
        ),
      );
    }

    // The adaptive list carries a dozen audio renditions; only the highest
    // bitrate one is worth offering.
    Map<String, dynamic>? bestAudio;
    for (final entry in streamingData?['adaptiveFormats'] as List<dynamic>? ?? []) {
      final format = entry as Map<String, dynamic>;
      if (!(format['mimeType']?.toString() ?? '').startsWith('audio/')) continue;
      if (usableUrl(format) == null) continue;
      final bitrate = (format['bitrate'] as num?) ?? 0;
      final bestBitrate = (bestAudio?['bitrate'] as num?) ?? -1;
      if (bitrate > bestBitrate) bestAudio = format;
    }

    if (bestAudio != null) {
      final kbps = (((bestAudio['bitrate'] as num?) ?? 128000) / 1000).round();
      qualities.add(
        VideoQualityOption(
          id: 'yt_audio_$videoId',
          label: 'Âm thanh M4A ($kbps kbps)',
          quality: 'Audio ($kbps kbps)',
          format: 'm4a',
          downloadUrl: bestAudio['url'].toString(),
          sizeBytes: int.tryParse(bestAudio['contentLength']?.toString() ?? ''),
          isAudioOnly: true,
        ),
      );
    }

    if (qualities.isEmpty) {
      throw ExtractionException(
        hasCipheredStreams
            ? 'Video này dùng luồng có chữ ký bảo vệ, bản web không giải mã được. '
                'Hãy dùng ứng dụng Android / iOS / Desktop để tải.'
            : 'Không tìm thấy luồng tải nào cho video YouTube này.',
      );
    }

    return VideoMetadata(
      id: videoId,
      originalUrl: url,
      title: details['title']?.toString() ?? 'YouTube Video',
      description: details['shortDescription']?.toString(),
      author: details['author']?.toString() ?? 'YouTube Creator',
      coverUrl: 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg',
      duration: _durationFrom(details['lengthSeconds']),
      platform: VideoPlatform.youtube,
      qualities: QualityHelper.sortedByQuality(qualities),
      viewCount: int.tryParse(details['viewCount']?.toString() ?? ''),
    );
  }

  Duration? _durationFrom(Object? lengthSeconds) {
    final seconds = int.tryParse(lengthSeconds?.toString() ?? '');
    return seconds != null && seconds > 0 ? Duration(seconds: seconds) : null;
  }
}
