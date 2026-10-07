import '../../models/video_metadata.dart';

class MediaSelectionHelper {
  const MediaSelectionHelper._();

  /// The key a video is checked by: everything sharing it is the same video
  /// offered at different qualities.
  static String videoKeyOf(VideoQualityOption option) =>
      option.mediaId ?? 'primary-video';

  /// The option a player should be given to preview [option]'s video.
  ///
  /// A quality that is joined on the device from separate picture and sound
  /// streams, such as YouTube above 360p, has nothing to play before it is
  /// downloaded. The same video at a quality that does is previewed in its
  /// place; [option] itself comes back when no quality of it can be played.
  static VideoQualityOption previewOptionFor(
    VideoQualityOption option,
    List<VideoQualityOption> options,
  ) {
    if (option.previewUrl.isNotEmpty) return option;
    final key = videoKeyOf(option);
    for (final candidate in options) {
      if (candidate.isImage || candidate.isAudioOnly) continue;
      if (candidate.previewUrl.isEmpty) continue;
      if (videoKeyOf(candidate) == key) return candidate;
    }
    return option;
  }

  /// One entry per video in [options], each the option to preview it with.
  static List<VideoQualityOption> previewPlaylist(
    List<VideoQualityOption> options,
  ) {
    final seen = <String>{};
    return [
      for (final option in options)
        if (!option.isImage && !option.isAudioOnly)
          if (seen.add(videoKeyOf(option))) previewOptionFor(option, options),
    ];
  }

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
