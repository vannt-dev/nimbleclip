import 'package:http/http.dart' as http;
import '../../models/video_metadata.dart';
import '../../models/video_platform.dart';
import 'base_extractor.dart';

class GenericExtractor implements BaseVideoExtractor {
  @override
  VideoPlatform get platform => VideoPlatform.generic;

  @override
  bool canHandle(String url) => true;

  @override
  Future<VideoMetadata> extract(String url) async {
    final cleanUrl = url.trim();
    final id = DateTime.now().millisecondsSinceEpoch.toString();

    // Check if it's already a direct video file extension
    final uri = Uri.parse(cleanUrl);
    final path = uri.path.toLowerCase();
    final isDirectVideo = path.endsWith('.mp4') ||
        path.endsWith('.mkv') ||
        path.endsWith('.webm') ||
        path.endsWith('.mov') ||
        path.endsWith('.mp3') ||
        path.endsWith('.m4a');

    if (isDirectVideo) {
      final fileName = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : 'Direct_Video_$id';
      final isAudio = path.endsWith('.mp3') || path.endsWith('.m4a');

      return VideoMetadata(
        id: id,
        originalUrl: cleanUrl,
        title: fileName,
        description: 'Direct Media Link',
        author: uri.host,
        authorAvatar: null,
        coverUrl: '',
        duration: null,
        platform: VideoPlatform.generic,
        qualities: [
          VideoQualityOption(
            id: 'gen_$id',
            label: isAudio ? 'Audio File' : 'Direct Video File',
            quality: 'Original',
            format: isAudio ? 'mp3' : 'mp4',
            downloadUrl: cleanUrl,
            isAudioOnly: isAudio,
          ),
        ],
        viewCount: null,
        likeCount: null,
        commentCount: null,
        shareCount: null,
      );
    }

    try {
      final response = await http.get(
        Uri.parse(cleanUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 10));

      final contentType = response.headers['content-type'] ?? '';
      if (contentType.startsWith('video/')) {
        return VideoMetadata(
          id: id,
          originalUrl: cleanUrl,
          title: 'Web Video ($id)',
          description: null,
          author: uri.host,
          authorAvatar: null,
          coverUrl: '',
          duration: null,
          platform: VideoPlatform.generic,
          qualities: [
            VideoQualityOption(
              id: 'gen_$id',
              label: 'Original Video Stream',
              quality: 'Original',
              format: 'mp4',
              downloadUrl: cleanUrl,
              sizeBytes: int.tryParse(response.headers['content-length'] ?? ''),
              isAudioOnly: false,
            ),
          ],
          viewCount: null,
          likeCount: null,
          commentCount: null,
          shareCount: null,
        );
      }

      // Check og:video in HTML
      final html = response.body;
      final ogVideo = RegExp(r'property="og:video(?::url)?"\s+content="([^"]+)"')
          .firstMatch(html);
      final ogTitle = RegExp(r'property="og:title"\s+content="([^"]+)"')
          .firstMatch(html);
      final ogImage = RegExp(r'property="og:image"\s+content="([^"]+)"')
          .firstMatch(html);

      if (ogVideo != null && ogVideo.group(1) != null) {
        final videoUrl = ogVideo.group(1)!;
        final title = ogTitle?.group(1) ?? 'Web Video';
        final image = ogImage?.group(1) ?? '';

        return VideoMetadata(
          id: id,
          originalUrl: cleanUrl,
          title: title,
          description: null,
          author: uri.host,
          authorAvatar: null,
          coverUrl: image,
          duration: null,
          platform: VideoPlatform.generic,
          qualities: [
            VideoQualityOption(
              id: 'gen_og_$id',
              label: 'Web Video Stream',
              quality: 'HD',
              format: 'mp4',
              downloadUrl: videoUrl,
              isAudioOnly: false,
            ),
          ],
          viewCount: null,
          likeCount: null,
          commentCount: null,
          shareCount: null,
        );
      }

      throw Exception('No playable video found at the provided URL.');
    } catch (e) {
      throw Exception('Generic extraction failed: $e');
    }
  }
}
