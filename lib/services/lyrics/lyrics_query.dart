/// What a lyrics lookup asks for: the artist and track name as a lyrics
/// catalogue would list them, and the track's length when it is known.
class LyricsQuery {
  const LyricsQuery({required this.artist, required this.track, this.duration});

  /// Empty when neither the title nor the uploader name an artist.
  final String artist;
  final String track;
  final Duration? duration;

  /// Builds the query for a download from its title and uploader.
  ///
  /// A title written as `Artist - Song` names the artist itself, which is
  /// usually closer to the catalogue than the uploader's name; otherwise the
  /// uploader is taken as the artist. Returns null when no track name is
  /// left once the title is cleaned.
  static LyricsQuery? forDownload({
    required String title,
    required String author,
    Duration? duration,
  }) {
    final cleaned = cleanTrackTitle(title);
    final dash = _artistSeparator.firstMatch(cleaned);
    String artist;
    String track;
    if (dash != null) {
      artist = cleanArtistName(cleaned.substring(0, dash.start));
      track = _stripQuotes(cleaned.substring(dash.end));
    } else {
      artist = cleanArtistName(author);
      track = _stripQuotes(cleaned);
    }
    if (track.isEmpty) return null;
    if (_unknownArtist.hasMatch(artist)) artist = '';
    return LyricsQuery(artist: artist, track: track, duration: duration);
  }
}

final RegExp _artistSeparator = RegExp(r'\s+[-–—]\s+');
final RegExp _unknownArtist = RegExp(r'^unknown$', caseSensitive: false);

/// Words that mark a bracketed part of a title as a note about the upload
/// rather than part of the song's name: `(Official Video)`, `[Lyrics]`.
final RegExp _noiseWords = RegExp(
  r'\b(official|video|audio|lyrics?|visuali[sz]er|mv|m/v|hd|hq|4k|explicit|'
  r'clip|color coded)\b',
  caseSensitive: false,
);

final RegExp _bracketed = RegExp(r'\s*[\(\[【]([^\)\]】]*)[\)\]】]');
final RegExp _featuringInBrackets = RegExp(
  r'^\s*(ft\.?|feat\.?|featuring)\s',
  caseSensitive: false,
);
final RegExp _featuring = RegExp(
  r'\s+(ft\.?|feat\.?|featuring)\s+.*?(?=\s+[-–—]\s+|\s*[\(\[【|｜]|$)',
  caseSensitive: false,
);
final RegExp _pipeTail = RegExp(r'\s*[|｜].*$');
final RegExp _spaces = RegExp(r'\s+');

/// A video title cut down to the song's name: drops bracketed notes such as
/// `(Official Video)` or `[Lyrics]`, a featured artist (`ft. X`), and
/// anything after a `|`. Other brackets, such as `(Acoustic)`, are kept.
String cleanTrackTitle(String title) {
  var text = title.replaceAll(_pipeTail, '');
  text = text.replaceAllMapped(_bracketed, (match) {
    final inside = match.group(1) ?? '';
    final noise =
        _noiseWords.hasMatch(inside) || _featuringInBrackets.hasMatch(inside);
    return noise ? '' : match.group(0)!;
  });
  text = text.replaceAll(_featuring, '');
  return text.replaceAll(_spaces, ' ').trim();
}

final RegExp _topicSuffix = RegExp(r'\s*-\s*Topic$', caseSensitive: false);
final RegExp _vevoSuffix = RegExp(r'\s*VEVO$');

/// An uploader's name as an artist: without the ` - Topic` of an
/// auto-generated channel, a trailing `VEVO`, or a featured artist.
String cleanArtistName(String name) {
  var text = name
      .trim()
      .replaceAll(_topicSuffix, '')
      .replaceAll(_vevoSuffix, '');
  text = text.replaceAll(_featuring, '');
  return text.replaceAll(_spaces, ' ').trim();
}

String _stripQuotes(String text) {
  final trimmed = text.trim();
  const pairs = {'"': '"', '“': '”', "'": "'"};
  if (trimmed.length >= 2) {
    final close = pairs[trimmed[0]];
    if (close != null && trimmed.endsWith(close)) {
      return trimmed.substring(1, trimmed.length - 1).trim();
    }
  }
  return trimmed;
}
