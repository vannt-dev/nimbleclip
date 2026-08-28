import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/core/utils/media_format_helper.dart';
import 'package:nimble_clip/core/utils/media_url_helper.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/models/video_platform.dart';

void main() {
  group('MediaFormatHelper', () {
    test('normalizes declared and URL image formats', () {
      expect(
        MediaFormatHelper.inferImageFormat(
          'https://cdn.example/media',
          declaredFormat: 'JPEG',
        ),
        'jpg',
      );
      expect(
        MediaFormatHelper.inferImageFormat(
          'https://cdn.example/photo.WEBP?width=1200',
        ),
        'webp',
      );
      expect(
        MediaFormatHelper.inferImageFormat('https://cdn.example/media'),
        'jpg',
      );
    });

    test('detects image URLs without matching query text', () {
      expect(
        MediaFormatHelper.isImageUrl('https://cdn.example/a.png?q=1'),
        isTrue,
      );
      expect(
        MediaFormatHelper.isImageUrl('https://cdn.example/video.mp4?q=.jpg'),
        isFalse,
      );
    });
  });

  test('MediaUrlHelper decodes escaped public URLs', () {
    expect(
      MediaUrlHelper.decode(r'https:\/\/cdn.example\/a.jpg?x=1&amp;y=2'),
      'https://cdn.example/a.jpg?x=1&y=2',
    );
    expect(MediaUrlHelper.isHttp('https://cdn.example/a.jpg'), isTrue);
    expect(MediaUrlHelper.isHttp('file:///tmp/a.jpg'), isFalse);
  });

  test('bestQuality prioritizes video, then image, then audio', () {
    VideoMetadata metadata(List<VideoQualityOption> qualities) => VideoMetadata(
      id: 'post',
      originalUrl: 'https://example.com/post',
      title: 'Post',
      author: 'Author',
      coverUrl: '',
      platform: VideoPlatform.generic,
      qualities: qualities,
    );

    const image = VideoQualityOption.image(
      id: 'image',
      label: ImageIndex(1),
      format: 'jpg',
      downloadUrl: 'https://cdn.example/image.jpg',
    );
    const video = VideoQualityOption.video(
      id: 'video',
      label: OriginalMp4(),
      quality: '720p',
      format: 'mp4',
      downloadUrl: 'https://cdn.example/video.mp4',
    );
    const audio = VideoQualityOption.audio(
      id: 'audio',
      label: OriginalAudio(),
      quality: 'Audio',
      format: 'mp3',
      downloadUrl: 'https://cdn.example/audio.mp3',
    );

    expect(metadata([image, audio, video]).bestQuality, same(video));
    expect(metadata([audio, image]).bestQuality, same(image));
    expect(metadata([audio]).bestQuality, same(audio));
  });
}
