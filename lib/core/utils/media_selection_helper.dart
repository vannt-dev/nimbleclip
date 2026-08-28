import '../../models/video_metadata.dart';

class MediaSelectionHelper {
  const MediaSelectionHelper._();

  /// The key a video is checked by: everything sharing it is the same video
  /// offered at different qualities.
  static String videoKeyOf(VideoQualityOption option) =>
      option.mediaId ?? 'primary-video';

  /// Selects one quality for each checked video plus every checked image.
  /// Audio is mutually exclusive with visual media.
  ///
  /// Which videos to take and which quality to take one at are separate
  /// choices: [selectedVideoIds] answers the first, [selectedQuality] the
  /// second. A post holding several videos would otherwise download all of
  /// them, which a story highlight makes untenable.
  static List<VideoQualityOption> downloads({
    required List<VideoQualityOption> options,
    required VideoQualityOption? selectedQuality,
    required Set<String> selectedImageIds,
    required Set<String> selectedVideoIds,
  }) {
    if (selectedQuality?.isAudioOnly == true) return [selectedQuality!];

    final selected = <VideoQualityOption>[];
    final videoGroups = <String, List<VideoQualityOption>>{};
    for (final option in options) {
      if (option.isAudioOnly || option.isImage) continue;
      (videoGroups[videoKeyOf(option)] ??= []).add(option);
    }
    for (final entry in videoGroups.entries) {
      if (!selectedVideoIds.contains(entry.key)) continue;
      final group = entry.value;
      selected.add(
        group.any((option) => option.id == selectedQuality?.id)
            ? selectedQuality!
            : group.first,
      );
    }
    selected.addAll(
      options.where(
        (option) => option.isImage && selectedImageIds.contains(option.id),
      ),
    );
    return selected;
  }
}
