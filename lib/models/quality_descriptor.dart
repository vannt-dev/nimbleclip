/// What a download option is, in terms the reader's language can be applied to.
///
/// Extractors describe an option rather than name it, so the layer produces no
/// presentation text and needs no localizations. `describeQuality` turns one
/// into a sentence at the moment it is shown or recorded.
sealed class QualityDescriptor {
  const QualityDescriptor();
}

/// The nth image of a carousel or gallery.
class ImageIndex extends QualityDescriptor {
  const ImageIndex(this.index);
  final int index;
}

class Hd720 extends QualityDescriptor {
  const Hd720();
}

class Sd480 extends QualityDescriptor {
  const Sd480();
}

class OriginalVideo extends QualityDescriptor {
  const OriginalVideo();
}

class OriginalMp4 extends QualityDescriptor {
  const OriginalMp4();
}

class OriginalAudio extends QualityDescriptor {
  const OriginalAudio();
}

class EmbeddedVideo extends QualityDescriptor {
  const EmbeddedVideo();
}

/// An audio track named after the sound it carries.
class AudioMp3 extends QualityDescriptor {
  const AudioMp3(this.title);
  final String title;
}

class AudioM4a extends QualityDescriptor {
  const AudioM4a(this.kbps);
  final int kbps;
}

/// A muxed stream carrying both picture and sound.
class VideoWithAudio extends QualityDescriptor {
  const VideoWithAudio(this.quality);
  final String quality;
}

/// TikTok serves the same video with and without its overlay.
class WatermarkedVideo extends QualityDescriptor {
  const WatermarkedVideo(this.quality, {required this.watermarked});
  final String quality;
  final bool watermarked;
}

/// A stream distinguished from its siblings by bitrate rather than resolution.
class VideoBitrate extends QualityDescriptor {
  const VideoBitrate(this.quality, this.kbps);
  final String quality;
  final int kbps;
}

/// Text carried over from a payload written before descriptors existed.
///
/// Produced only by [VideoQualityOption.fromJson], never by an extractor.
/// Analysis history written before the 1.3.0 compact migration embeds whole
/// serialized options; the one reader of that path discards the qualities, so
/// this exists to keep deserialization from throwing rather than to be shown.
class LiteralLabel extends QualityDescriptor {
  const LiteralLabel(this.text);
  final String text;
}
