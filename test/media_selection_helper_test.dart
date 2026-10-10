import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/core/utils/media_selection_helper.dart';
import 'package:nimble_clip/models/merge_source.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/models/video_metadata.dart';

void main() {
  VideoQualityOption video(String id, String mediaId) =>
      VideoQualityOption.video(
        id: id,
        mediaId: mediaId,
        label: const OriginalMp4(),
        quality: id,
        format: 'mp4',
        downloadUrl: 'https://example.com/$id.mp4',
      );

  VideoQualityOption image(String id, int index) => VideoQualityOption.image(
    id: id,
    mediaId: id,
    label: ImageIndex(index),
    quality: 'Original',
    format: 'jpg',
    downloadUrl: 'https://example.com/$id.jpg',
  );

  test('selects one quality per video and checked images', () {
    final firstHd = video('first-hd', 'first');
    final firstSd = video('first-sd', 'first');
    final second = video('second', 'second');
    final imageOne = image('image-1', 1);
    final imageTwo = image('image-2', 2);

    final selected = MediaSelectionHelper.downloads(
      options: [firstHd, firstSd, second, imageOne, imageTwo],
      selectedQuality: firstSd,
      selectedImageIds: {'image-2'},
      selectedVideoIds: {'first', 'second'},
    );

    expect(selected, [firstSd, second, imageTwo]);
  });

  test('an unchecked video is left out', () {
    // A story highlight can hold a dozen videos. Downloading every one of
    // them because the reader wanted two is the behaviour this replaces.
    final first = video('first', 'first');
    final second = video('second', 'second');
    final third = video('third', 'third');

    expect(
      MediaSelectionHelper.downloads(
        options: [first, second, third],
        selectedQuality: first,
        selectedImageIds: const {},
        selectedVideoIds: {'first', 'third'},
      ),
      [first, third],
    );
  });

  test('unchecking every video leaves nothing to download', () {
    final only = video('only', 'only');

    expect(
      MediaSelectionHelper.downloads(
        options: [only],
        selectedQuality: only,
        selectedImageIds: const {},
        selectedVideoIds: const {},
      ),
      isEmpty,
    );
  });

  test('the chosen quality still wins inside a checked video', () {
    // Picking which videos to take and picking a quality for one of them are
    // separate choices; checking a video must not discard the quality.
    final hd = video('first-hd', 'first');
    final sd = video('first-sd', 'first');

    expect(
      MediaSelectionHelper.downloads(
        options: [hd, sd],
        selectedQuality: sd,
        selectedImageIds: const {},
        selectedVideoIds: {'first'},
      ),
      [sd],
    );
  });

  test('audio selection excludes visual media', () {
    final audio = VideoQualityOption.audio(
      id: 'audio',
      label: const OriginalAudio(),
      quality: 'Audio',
      format: 'mp3',
      downloadUrl: 'https://example.com/audio.mp3',
    );

    expect(
      MediaSelectionHelper.downloads(
        options: [video('video', 'video'), image('image', 1), audio],
        selectedQuality: audio,
        selectedImageIds: {'image'},
        selectedVideoIds: {'video'},
      ),
      [audio],
    );
  });

  group('what a preview plays', () {
    VideoQualityOption merged(String id, String? mediaId) =>
        VideoQualityOption.merged(
          id: id,
          mediaId: mediaId,
          label: const OriginalMp4(),
          quality: id,
          source: const MergeSource(
            videoUrl: 'https://example.com/picture.mp4',
            audioUrl: 'https://example.com/sound.m4a',
            partBytes: 1 << 20,
          ),
        );

    test('a quality joined on the device is previewed at one that plays', () {
      // YouTube on Android: 1080p and 720p are joined, 360p comes whole.
      final hd = merged('1080p', null);
      final mid = merged('720p', null);
      final sd = VideoQualityOption.video(
        id: '360p',
        label: const OriginalMp4(),
        quality: '360p',
        format: 'mp4',
        downloadUrl: 'https://example.com/360.mp4',
      );
      final audio = VideoQualityOption(
        id: 'audio',
        label: const OriginalMp4(),
        quality: 'Audio',
        format: 'm4a',
        downloadUrl: 'https://example.com/sound.m4a',
        kind: MediaKind.audio,
      );
      final options = [hd, mid, sd, audio];

      expect(hd.previewUrl, isEmpty);
      expect(MediaSelectionHelper.previewOptionFor(hd, options), sd);
      expect(MediaSelectionHelper.previewOptionFor(mid, options), sd);
      expect(MediaSelectionHelper.previewOptionFor(sd, options), sd);
      // One entry for the one video, and it is the one that can be played.
      expect(MediaSelectionHelper.previewPlaylist(options), [sd]);
    });

    test('another video is never played in its place', () {
      final first = merged('first-1080p', 'first');
      final second = video('second', 'second');
      final options = [first, second];

      expect(MediaSelectionHelper.previewOptionFor(first, options), first);
      expect(MediaSelectionHelper.previewPlaylist(options), [first, second]);
    });

    test('an option that already plays is left as it is', () {
      final hd = video('first-hd', 'first');
      final sd = video('first-sd', 'first');
      final picture = image('image-1', 1);
      final options = [hd, sd, picture];

      expect(MediaSelectionHelper.previewOptionFor(sd, options), sd);
      expect(MediaSelectionHelper.previewPlaylist(options), [hd]);
    });
  });
}
