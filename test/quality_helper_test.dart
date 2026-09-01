import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/core/utils/quality_helper.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/models/slideshow_source.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/models/video_platform.dart';

VideoQualityOption option(
  String quality, {
  bool audio = false,
  int? sizeBytes,
  String? id,
}) {
  return VideoQualityOption(
    id: id ?? quality,
    label: audio ? const OriginalAudio() : const OriginalMp4(),
    quality: quality,
    format: audio ? 'mp3' : 'mp4',
    downloadUrl: 'https://cdn.example.com/${quality.replaceAll(' ', '_')}.mp4',
    sizeBytes: sizeBytes,
    kind: audio ? MediaKind.audio : MediaKind.video,
  );
}

/// A photo as the extractors actually build one: `VideoQualityOption.image`
/// defaults `quality` to the literal 'Original'.
VideoQualityOption imageOption(String id) => VideoQualityOption.image(
  id: id,
  mediaId: id,
  label: const ImageIndex(1),
  format: 'jpg',
  downloadUrl: 'https://cdn.example.com/$id.jpg',
);

void main() {
  group('a post carrying both photos and video', () {
    // Regression: `quality` on an image is the word 'Original', which the
    // named-height table reads as 2160. That ranked every photo above every
    // video, so the default selection landed on a photo and the video tab —
    // which lists only video options — showed nothing selected.
    final mixed = [option('720p', id: 'video'), imageOption('photo')];

    test('an image never outranks a video', () {
      expect(
        QualityHelper.rankOf(imageOption('photo')),
        lessThan(QualityHelper.rankOf(option('360p'))),
      );
    });

    test('sorting puts the video ahead of the photo', () {
      expect(
        QualityHelper.sortedByQuality([
          imageOption('photo'),
          option('720p', id: 'video'),
        ]).first.id,
        'video',
      );
    });

    test('Highest selects the video, not the photo', () {
      expect(QualityHelper.bestMatch(mixed, 'Highest')!.id, 'video');
    });

    test('a resolution preference selects the video, not the photo', () {
      // The photo used to be the only option ranked at or below 720.
      expect(
        QualityHelper.bestMatch([
          option('1080p', id: 'video'),
          imageOption('photo'),
        ], '720p')!.id,
        'video',
      );
    });

    test('a post of photos alone still selects a photo', () {
      expect(
        QualityHelper.bestMatch([
          imageOption('photo-1'),
          imageOption('photo-2'),
        ], 'Highest')!.id,
        'photo-1',
      );
    });
  });

  group('QualityHelper.parseHeight', () {
    test('reads explicit resolutions', () {
      expect(QualityHelper.parseHeight('1080p'), 1080);
      expect(QualityHelper.parseHeight('720p60'), 720);
      expect(QualityHelper.parseHeight('1920x1080'), 1080);
    });

    test('prefers a written resolution over a quality word', () {
      // "HD 1080p" must not collapse to HD's nominal 720.
      expect(QualityHelper.parseHeight('HD 1080p'), 1080);
      expect(QualityHelper.parseHeight('SD 720p'), 720);
    });

    test('falls back to named tiers', () {
      expect(QualityHelper.parseHeight('HD'), 720);
      expect(QualityHelper.parseHeight('SD'), 480);
      expect(QualityHelper.parseHeight('Original'), 2160);
    });

    test('returns null when nothing is recognisable', () {
      expect(QualityHelper.parseHeight(''), isNull);
      expect(QualityHelper.parseHeight('Audio'), isNull);
    });
  });

  group('QualityHelper.sortedByQuality', () {
    test('orders video best-first and sinks audio to the end', () {
      final sorted = QualityHelper.sortedByQuality([
        option('480p'),
        option('Audio MP3', audio: true),
        option('1080p'),
        option('720p'),
      ]);

      expect(sorted.map((o) => o.quality).toList(), [
        '1080p',
        '720p',
        '480p',
        'Audio MP3',
      ]);
    });

    test('is stable for options of equal rank', () {
      final sorted = QualityHelper.sortedByQuality([
        option('720p', id: 'first'),
        option('720p', id: 'second'),
      ]);
      expect(sorted.map((o) => o.id).toList(), ['first', 'second']);
    });
  });

  group('QualityHelper.bestMatch', () {
    final options = [
      option('1080p'),
      option('720p'),
      option('480p'),
      option('360p'),
      option('Audio MP3', audio: true),
    ];

    test('Highest picks the top video, never audio', () {
      expect(QualityHelper.bestMatch(options, 'Highest')!.quality, '1080p');
    });

    test('Audio picks the audio track', () {
      expect(QualityHelper.bestMatch(options, 'Audio')!.quality, 'Audio MP3');
    });

    test('an exact resolution preference is honoured', () {
      expect(QualityHelper.bestMatch(options, '720p')!.quality, '720p');
      expect(QualityHelper.bestMatch(options, '480p')!.quality, '480p');
      expect(QualityHelper.bestMatch(options, '360p')!.quality, '360p');
    });

    test('a "SD 720p" label does not satisfy a 360p preference', () {
      // Regression: substring matching on the label used to select TikTok's
      // "SD 720p" for someone who asked for 360p.
      final tiktok = [option('HD 1080p'), option('SD 720p')];
      expect(QualityHelper.bestMatch(tiktok, '360p')!.quality, 'SD 720p');
      expect(QualityHelper.bestMatch(tiktok, 'Highest')!.quality, 'HD 1080p');
    });

    test('falls back to the closest option at or below the target', () {
      final sparse = [option('1080p'), option('480p')];
      expect(QualityHelper.bestMatch(sparse, '720p')!.quality, '480p');
    });

    test('uses the lowest option when everything exceeds the target', () {
      final tall = [option('2160p'), option('1080p')];
      expect(QualityHelper.bestMatch(tall, '360p')!.quality, '1080p');
    });

    test('returns audio when that is all there is', () {
      final audioOnly = [option('Audio MP3', audio: true)];
      expect(
        QualityHelper.bestMatch(audioOnly, 'Highest')!.isAudioOnly,
        isTrue,
      );
    });

    test('returns null for an empty list', () {
      expect(QualityHelper.bestMatch(const [], 'Highest'), isNull);
    });
  });

  test('a slideshow never becomes the default selection', () {
    const image = VideoQualityOption.image(
      id: 'i1',
      label: ImageIndex(1),
      format: 'jpg',
      downloadUrl: 'https://cdn/1.jpg',
    );
    const slideshow = VideoQualityOption.slideshow(
      id: 's1',
      label: SlideshowVideo(1),
      source: SlideshowSource(imageUrls: ['https://cdn/1.jpg']),
    );
    final best = QualityHelper.bestMatch([image, slideshow], 'Highest');
    expect(best!.isImage, isTrue);
  });

  test('bestQuality skips a slideshow and still reports the image', () {
    // Guards the default selection: bestQuality feeds selectedQuality in
    // video_extractor_provider, so a slideshow winning here would move a photo
    // post's default onto the video tab.
    const image = VideoQualityOption.image(
      id: 'i1',
      label: ImageIndex(1),
      format: 'jpg',
      downloadUrl: 'https://cdn/1.jpg',
    );
    const slideshow = VideoQualityOption.slideshow(
      id: 's1',
      label: SlideshowVideo(1),
      source: SlideshowSource(imageUrls: ['https://cdn/1.jpg']),
    );
    final metadata = VideoMetadata(
      id: 'p',
      originalUrl: 'https://tiktok.com/@u/photo/1',
      title: 'photo post',
      author: 'someone',
      coverUrl: '',
      platform: VideoPlatform.tiktok,
      qualities: const [image, slideshow],
    );
    expect(metadata.bestQuality, same(image));
  });

  test('a slideshow does not outrank a real video', () {
    const video = VideoQualityOption.video(
      id: 'v',
      label: OriginalMp4(),
      quality: '720p',
      format: 'mp4',
      downloadUrl: 'https://cdn/v.mp4',
    );
    const slideshow = VideoQualityOption.slideshow(
      id: 's1',
      label: SlideshowVideo(1),
      source: SlideshowSource(imageUrls: ['https://cdn/1.jpg']),
    );
    expect(
      QualityHelper.rankOf(video) > QualityHelper.rankOf(slideshow),
      isTrue,
    );
  });
}
