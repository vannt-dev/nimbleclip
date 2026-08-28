import '../../models/video_metadata.dart';

/// Turns the free-form quality strings the extractors produce ("1080p",
/// "HD 1080p", "SD", "Original") into a comparable pixel height.
///
/// Sorting and preference matching both need a number: substring matching on
/// the label is what made a preference of "360p" select TikTok's "SD 720p"
/// option, because that label happens to contain "SD".
class QualityHelper {
  static const Map<String, int> _namedHeights = {
    'original': 2160,
    'source': 2160,
    'uhd': 2160,
    '4k': 2160,
    'fhd': 1080,
    'fullhd': 1080,
    'hd': 720,
    'sd': 480,
    'ld': 360,
    'low': 240,
  };

  /// Pixel height implied by [text], or null when nothing recognisable is there.
  static int? parseHeight(String text) {
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();

    // Explicit resolutions win: "HD 1080p" is 1080, not 720.
    final resolution =
        _progressiveHeight.firstMatch(lower) ?? _dimensions.firstMatch(lower);
    if (resolution != null) {
      final value = int.tryParse(resolution.group(1)!);
      if (value != null && value >= 100 && value <= 4320) return value;
    }

    for (final entry in _namedHeightPatterns.entries) {
      if (entry.value.hasMatch(lower)) return _namedHeights[entry.key];
    }
    return null;
  }

  static final RegExp _progressiveHeight = RegExp(r'(\d{3,4})\s*p');
  static final RegExp _dimensions = RegExp(r'\d{3,4}\s*[x×]\s*(\d{3,4})');

  /// One compiled word-boundary pattern per named tier. `parseHeight` runs for
  /// every option while sorting, so building these per call recompiled the
  /// whole table on each comparison.
  static final Map<String, RegExp> _namedHeightPatterns = {
    for (final key in _namedHeights.keys) key: RegExp('\\b$key\\b'),
  };

  /// Rank used for ordering: video first, then images, then audio, so neither
  /// `bestQuality` nor the "Highest" preference lands on a photo or a track.
  static int rankOf(VideoQualityOption option) {
    if (option.isAudioOnly) return -1;
    // An image carries no resolution: `VideoQualityOption.image` leaves
    // `quality` at the literal 'Original', which the named-height table reads
    // as 2160. Parsing it ranked every photo above every video, so a post
    // holding both selected a photo by default and its video tab — which lists
    // video options only — came up with nothing selected.
    if (option.isImage) return 0;
    // `label` used to be a second place to look for a resolution. It is now a
    // descriptor with no text to parse, and every option sets `quality`, which
    // is the field this was backing up.
    return parseHeight(option.quality) ?? 1;
  }

  /// Returns [options] ordered best-first. Stable for equal ranks, so the order
  /// the extractor produced is preserved within a tier.
  static List<VideoQualityOption> sortedByQuality(
    List<VideoQualityOption> options,
  ) {
    final indexed = options.indexed.toList();
    indexed.sort((a, b) {
      final byRank = rankOf(b.$2).compareTo(rankOf(a.$2));
      if (byRank != 0) return byRank;
      final bySize = (b.$2.sizeBytes ?? 0).compareTo(a.$2.sizeBytes ?? 0);
      if (bySize != 0) return bySize;
      return a.$1.compareTo(b.$1);
    });
    return indexed.map((entry) => entry.$2).toList();
  }

  /// Picks the option that best matches a user preference of 'Highest',
  /// 'Audio', or a resolution like '720p'.
  ///
  /// For a resolution preference the closest option at or below the target is
  /// chosen; if every option is higher, the lowest one is used. That avoids
  /// silently handing a 1080p file to someone who asked for 360p.
  static VideoQualityOption? bestMatch(
    List<VideoQualityOption> options,
    String preferred,
  ) {
    if (options.isEmpty) return null;
    final sorted = sortedByQuality(options);

    if (preferred == 'Audio') {
      for (final option in sorted) {
        if (option.isAudioOnly) return option;
      }
      return sorted.first;
    }

    final videoOnly = sorted
        .where((o) => !o.isAudioOnly && !o.isImage)
        .toList();
    if (videoOnly.isEmpty) return sorted.first;

    if (preferred == 'Highest') return videoOnly.first;

    final target = parseHeight(preferred);
    if (target == null) return videoOnly.first;

    final atOrBelow = videoOnly.where((o) => rankOf(o) <= target).toList();
    if (atOrBelow.isNotEmpty) return atOrBelow.first;
    return videoOnly.last;
  }
}
