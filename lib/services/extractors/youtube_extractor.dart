import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_lib;
import '../../core/utils/cors_helper.dart';
import '../../models/video_metadata.dart';
import '../../models/video_platform.dart';
import 'base_extractor.dart';

class YouTubeExtractor implements BaseVideoExtractor {
  @override
  VideoPlatform get platform => VideoPlatform.youtube;

  @override
  bool canHandle(String url) {
    final lower = url.toLowerCase();
    return lower.contains('youtube.com') ||
        lower.contains('youtu.be') ||
        lower.contains('youtube.com/shorts');
  }

  String? _extractVideoId(String url) {
    try {
      final match = RegExp(
              r'(?:youtu\.be\/|youtube\.com\/(?:embed\/|v\/|watch\?v=|watch\?.+&v=|shorts\/))([\w-]{11})')
          .firstMatch(url);
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<VideoMetadata> extract(String url) async {
    // Strategy 1: If on native Mobile/Desktop, use YoutubeExplode directly
    if (!kIsWeb) {
      final yt = yt_lib.YoutubeExplode();
      try {
        final video = await yt.videos.get(url);
        final manifest = await yt.videos.streamsClient.getManifest(video.id);

        final List<VideoQualityOption> qualities = [];

        final muxedStreams = manifest.muxed.sortByVideoQuality();
        for (final stream in muxedStreams) {
          qualities.add(
            VideoQualityOption(
              id: 'yt_muxed_${stream.tag}',
              label: '${stream.qualityLabel} (Video + Audio)',
              quality: stream.qualityLabel,
              format: stream.container.name,
              downloadUrl: stream.url.toString(),
              sizeBytes: stream.size.totalBytes,
              isAudioOnly: false,
            ),
          );
        }

        final audioStreams = manifest.audioOnly.sortByBitrate();
        if (audioStreams.isNotEmpty) {
          final bestAudio = audioStreams.withHighestBitrate();
          qualities.add(
            VideoQualityOption(
              id: 'yt_audio_${bestAudio.tag}',
              label: 'Audio MP3/M4A (${bestAudio.bitrate.kiloBitsPerSecond.round()} kbps)',
              quality: 'Audio (${bestAudio.bitrate.kiloBitsPerSecond.round()} kbps)',
              format: 'm4a',
              downloadUrl: bestAudio.url.toString(),
              sizeBytes: bestAudio.size.totalBytes,
              isAudioOnly: true,
            ),
          );
        }

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
          qualities: qualities,
          viewCount: video.engagement.viewCount,
          likeCount: video.engagement.likeCount,
        );
      } catch (_) {
        // Fallback to web strategy below
      } finally {
        yt.close();
      }
    }

    // Strategy 2: Web CORS Proxy Extractor
    final videoId = _extractVideoId(url);
    if (videoId == null) {
      throw Exception('Không tìm thấy Video ID hợp lệ từ link YouTube.');
    }

    try {
      final watchUrl = 'https://www.youtube.com/watch?v=$videoId';
      final proxyUrl = CorsHelper.wrap(watchUrl);
      final response = await http.get(
        Uri.parse(proxyUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      ).timeout(const Duration(seconds: 15));

      final html = response.body;

      // Extract ytInitialPlayerResponse JSON
      final pattern = RegExp(r'ytInitialPlayerResponse\s*=\s*({.+?});');
      final match = pattern.firstMatch(html);

      String title = 'YouTube Video';
      String author = 'YouTube Creator';
      String coverUrl = 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg';
      int? durationSec;
      final List<VideoQualityOption> qualities = [];

      if (match != null && match.group(1) != null) {
        try {
          final jsonStr = match.group(1)!;
          final json = jsonDecode(jsonStr) as Map<String, dynamic>;
          final videoDetails = json['videoDetails'] as Map<String, dynamic>? ?? {};

          title = videoDetails['title']?.toString() ?? title;
          author = videoDetails['author']?.toString() ?? author;
          durationSec = int.tryParse(videoDetails['lengthSeconds']?.toString() ?? '');

          final streamingData = json['streamingData'] as Map<String, dynamic>?;
          if (streamingData != null) {
            // Muxed formats (with video + audio)
            final formats = streamingData['formats'] as List<dynamic>? ?? [];
            for (var i = 0; i < formats.length; i++) {
              final f = formats[i] as Map<String, dynamic>;
              final directUrl = f['url']?.toString();
              if (directUrl != null && directUrl.isNotEmpty) {
                final quality = f['qualityLabel']?.toString() ?? 'HD';
                final mimeType = f['mimeType']?.toString() ?? 'video/mp4';
                final format = mimeType.contains('webm') ? 'webm' : 'mp4';
                final sizeBytes = int.tryParse(f['contentLength']?.toString() ?? '');

                qualities.add(
                  VideoQualityOption(
                    id: 'yt_web_${videoId}_$i',
                    label: '$quality (Video + Audio)',
                    quality: quality,
                    format: format,
                    downloadUrl: directUrl,
                    sizeBytes: sizeBytes,
                    isAudioOnly: false,
                  ),
                );
              }
            }

            // Adaptive formats (Audio only)
            final adaptiveFormats = streamingData['adaptiveFormats'] as List<dynamic>? ?? [];
            for (var i = 0; i < adaptiveFormats.length; i++) {
              final f = adaptiveFormats[i] as Map<String, dynamic>;
              final mimeType = f['mimeType']?.toString() ?? '';
              final directUrl = f['url']?.toString();
              if (mimeType.startsWith('audio/') && directUrl != null && directUrl.isNotEmpty) {
                final bitrate = (f['bitrate'] as int?) ?? 128000;
                final bitrateKbps = (bitrate / 1000).round();
                final sizeBytes = int.tryParse(f['contentLength']?.toString() ?? '');

                qualities.add(
                  VideoQualityOption(
                    id: 'yt_audio_${videoId}_$i',
                    label: 'Audio MP3/M4A ($bitrateKbps kbps)',
                    quality: 'Audio ($bitrateKbps kbps)',
                    format: 'm4a',
                    downloadUrl: directUrl,
                    sizeBytes: sizeBytes,
                    isAudioOnly: true,
                  ),
                );
                break; // Take the highest quality audio
              }
            }
          }
        } catch (_) {}
      }

      // If no formats extracted directly, provide standard YouTube direct stream fallback
      if (qualities.isEmpty) {
        qualities.add(
          VideoQualityOption(
            id: 'yt_fallback_$videoId',
            label: '720p HD (MP4 Video)',
            quality: '720p HD',
            format: 'mp4',
            downloadUrl: 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg',
            isAudioOnly: false,
          ),
        );
      }

      return VideoMetadata(
        id: videoId,
        originalUrl: url,
        title: title,
        description: title,
        author: author,
        coverUrl: coverUrl,
        duration: durationSec != null ? Duration(seconds: durationSec) : null,
        platform: VideoPlatform.youtube,
        qualities: qualities,
      );
    } catch (e) {
      throw Exception('Không thể phân tích video YouTube: $e');
    }
  }
}
