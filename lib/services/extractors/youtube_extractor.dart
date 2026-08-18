import 'package:youtube_explode_dart/youtube_explode_dart.dart';
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

  @override
  Future<VideoMetadata> extract(String url) async {
    final yt = YoutubeExplode();
    try {
      final video = await yt.videos.get(url);
      final manifest = await yt.videos.streamsClient.getManifest(video.id);

      final List<VideoQualityOption> qualities = [];

      // 1. Muxed streams (Video + Audio combined in single container)
      final muxedStreams = manifest.muxed.sortByVideoQuality();
      for (final stream in muxedStreams) {
        final qualityLabel = '${stream.qualityLabel} (Video + Audio)';
        qualities.add(
          VideoQualityOption(
            id: 'yt_muxed_${stream.tag}',
            label: qualityLabel,
            quality: stream.qualityLabel,
            format: stream.container.name,
            downloadUrl: stream.url.toString(),
            sizeBytes: stream.size.totalBytes,
            isAudioOnly: false,
          ),
        );
      }

      // 2. Video only streams if higher quality available (e.g., 1080p, 1440p, 4K)
      final videoStreams = manifest.videoOnly.sortByVideoQuality();
      for (final stream in videoStreams) {
        // Skip if already in muxed with same quality
        if (muxedStreams.any((m) => m.qualityLabel == stream.qualityLabel)) {
          continue;
        }
        qualities.add(
          VideoQualityOption(
            id: 'yt_video_${stream.tag}',
            label: '${stream.qualityLabel} (High Def)',
            quality: stream.qualityLabel,
            format: stream.container.name,
            downloadUrl: stream.url.toString(),
            sizeBytes: stream.size.totalBytes,
            isAudioOnly: false,
          ),
        );
      }

      // 3. Audio only streams (MP3/M4A)
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
        authorAvatar: null,
        coverUrl: video.thumbnails.highResUrl.isNotEmpty
            ? video.thumbnails.highResUrl
            : video.thumbnails.mediumResUrl,
        duration: video.duration,
        platform: VideoPlatform.youtube,
        qualities: qualities,
        viewCount: video.engagement.viewCount,
        likeCount: video.engagement.likeCount,
        commentCount: null,
        shareCount: null,
      );
    } catch (e) {
      throw Exception('Failed to extract YouTube video: $e');
    } finally {
      yt.close();
    }
  }
}
