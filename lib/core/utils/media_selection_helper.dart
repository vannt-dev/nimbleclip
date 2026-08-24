import '../../models/video_metadata.dart';

class MediaSelectionHelper {
  const MediaSelectionHelper._();

  /// Selects one quality for each video in a post plus every checked image.
  /// Audio is mutually exclusive with visual media.
  static List<VideoQualityOption> downloads({
    required List<VideoQualityOption> options,
    required VideoQualityOption? selectedQuality,
    required Set<String> selectedImageIds,
  }) {
    if (selectedQuality?.isAudioOnly == true) return [selectedQuality!];

    final selected = <VideoQualityOption>[];
    final videoGroups = <String, List<VideoQualityOption>>{};
    for (final option in options) {
      if (option.isAudioOnly || option.isImage) continue;
      (videoGroups[option.mediaId ?? 'primary-video'] ??= []).add(option);
    }
    for (final group in videoGroups.values) {
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
