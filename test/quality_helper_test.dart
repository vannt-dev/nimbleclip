import 'package:flutter_test/flutter_test.dart';
import 'package:snap_video/core/utils/quality_helper.dart';
import 'package:snap_video/models/video_metadata.dart';

VideoQualityOption option(
  String quality, {
  bool audio = false,
  int? sizeBytes,
  String? label,
}) {
  return VideoQualityOption(
    id: quality,
    label: label ?? quality,
    quality: quality,
    format: audio ? 'mp3' : 'mp4',
    downloadUrl: 'https://cdn.example.com/${quality.replaceAll(' ', '_')}.mp4',
    sizeBytes: sizeBytes,
    isAudioOnly: audio,
  );
}

void main() {
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

      expect(sorted.map((o) => o.quality).toList(),
          ['1080p', '720p', '480p', 'Audio MP3']);
    });

    test('is stable for options of equal rank', () {
      final sorted = QualityHelper.sortedByQuality([
        option('720p', label: 'first'),
        option('720p', label: 'second'),
      ]);
      expect(sorted.map((o) => o.label).toList(), ['first', 'second']);
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
      expect(QualityHelper.bestMatch(audioOnly, 'Highest')!.isAudioOnly, isTrue);
    });

    test('returns null for an empty list', () {
      expect(QualityHelper.bestMatch(const [], 'Highest'), isNull);
    });
  });
}
