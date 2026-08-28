import '../models/quality_descriptor.dart';
import 'generated/app_localizations.dart';

/// Names [descriptor] in the caller's language.
///
/// Exhaustive over the sealed hierarchy, so adding a descriptor without adding
/// its text is a compile error rather than a blank option in the list.
String describeQuality(QualityDescriptor descriptor, AppLocalizations l10n) {
  return switch (descriptor) {
    ImageIndex(:final index) => l10n.imageLabel(index),
    VideoIndex(:final index) => l10n.videoLabel(index),
    Hd720() => l10n.highQuality720,
    Sd480() => l10n.standardQuality480,
    OriginalVideo() => l10n.originalVideo,
    OriginalMp4() => l10n.originalMp4,
    OriginalAudio() => l10n.originalAudio,
    EmbeddedVideo() => l10n.embeddedVideo,
    AudioMp3(:final title) => l10n.audioMp3Label(
      title == null || title.isEmpty ? l10n.originalSound : title,
    ),
    AudioM4a(:final kbps) => l10n.audioM4aLabel(kbps),
    VideoWithAudio(:final quality) => l10n.videoAndAudioLabel(quality),
    WatermarkedVideo(:final quality, :final watermarked) =>
      '$quality (${watermarked ? l10n.withWatermark : l10n.noWatermark})',
    // X distinguishes its variants by bitrate. This was previously built as a
    // hardcoded string and never translated; giving it a descriptor brings it
    // in line with the rest.
    VideoBitrate(:final quality, :final kbps) => l10n.videoBitrateLabel(
      quality,
      kbps,
    ),
    LiteralLabel(:final text) => text,
  };
}
