import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/core/utils/media_format_helper.dart';
import 'package:nimble_clip/core/utils/media_url_helper.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/models/slideshow_source.dart';
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

    test('files every audio download under an audio type', () {
      expect(MediaFormatHelper.audioMimeType('Song.mp3'), 'audio/mpeg');
      expect(MediaFormatHelper.audioMimeType('Song.M4A'), 'audio/mp4');
      expect(MediaFormatHelper.audioMimeType('Song.opus'), 'audio/ogg');
      expect(MediaFormatHelper.audioMimeType('Song.aac'), 'audio/aac');
      // Extensions the platform would otherwise file as video.
      expect(MediaFormatHelper.audioMimeType('Song.webm'), 'audio/webm');
      expect(MediaFormatHelper.audioMimeType('Song.mp4'), 'audio/mp4');
      expect(MediaFormatHelper.audioMimeType('Song.ogg'), 'audio/ogg');
      // A whole path, and a title that holds dots of its own.
      expect(
        MediaFormatHelper.audioMimeType('/files/NimbleClip/Vol. 2 - Intro.m4a'),
        'audio/mp4',
      );
      // Unknown or missing extensions still land in the audio collection.
      expect(MediaFormatHelper.audioMimeType('Song.xyz'), 'audio/mpeg');
      expect(MediaFormatHelper.audioMimeType('Song'), 'audio/mpeg');
    });

    test('files pictures and videos under the type their folder accepts', () {
      expect(MediaFormatHelper.imageMimeType('a.jpg'), 'image/jpeg');
      expect(MediaFormatHelper.imageMimeType('a.JPEG'), 'image/jpeg');
      expect(MediaFormatHelper.imageMimeType('a.png'), 'image/png');
      expect(MediaFormatHelper.imageMimeType('a.webp'), 'image/webp');
      expect(MediaFormatHelper.imageMimeType('a.gif'), 'image/gif');
      expect(MediaFormatHelper.imageMimeType('a.heic'), 'image/heic');
      // Unknown or missing extensions still land among the pictures.
      expect(MediaFormatHelper.imageMimeType('a.xyz'), 'image/jpeg');
      expect(MediaFormatHelper.imageMimeType('a'), 'image/jpeg');

      expect(MediaFormatHelper.videoMimeType('v.mp4'), 'video/mp4');
      expect(
        MediaFormatHelper.videoMimeType('/x/Vol. 2.MOV'),
        'video/quicktime',
      );
      expect(MediaFormatHelper.videoMimeType('v.webm'), 'video/webm');
      expect(MediaFormatHelper.videoMimeType('v.mkv'), 'video/x-matroska');
      expect(MediaFormatHelper.videoMimeType('v.3gp'), 'video/3gpp');
      expect(MediaFormatHelper.videoMimeType('v.xyz'), 'video/mp4');
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

  test('bestQuality skips a slideshow, which is not a file yet', () {
    VideoMetadata metadata(List<VideoQualityOption> qualities) => VideoMetadata(
      id: 'post',
      originalUrl: 'https://example.com/post',
      title: 'Post',
      author: 'Author',
      coverUrl: '',
      platform: VideoPlatform.tiktok,
      qualities: qualities,
    );

    const image = VideoQualityOption.image(
      id: 'image',
      label: ImageIndex(1),
      format: 'jpg',
      downloadUrl: 'https://cdn.example/image.jpg',
    );
    const slideshow = VideoQualityOption.slideshow(
      id: 'slideshow',
      label: SlideshowVideo(1),
      source: SlideshowSource(imageUrls: ['https://cdn.example/image.jpg']),
    );

    expect(metadata([image, slideshow]).bestQuality, same(image));
  });
}
