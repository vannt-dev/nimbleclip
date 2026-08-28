import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/core/utils/media_selection_helper.dart';
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
    );

    expect(selected, [firstSd, second, imageTwo]);
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
      ),
      [audio],
    );
  });
}
