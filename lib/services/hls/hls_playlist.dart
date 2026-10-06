/// One quality of a stream, as its master playlist lists it.
class HlsVariant {
  const HlsVariant({
    required this.url,
    required this.bandwidth,
    this.width,
    this.height,
    this.audioGroup,
    this.codecs,
  });

  final String url;
  final int bandwidth;
  final int? width;
  final int? height;

  /// The `AUDIO` group this quality plays with, when sound is a stream of its
  /// own.
  final String? audioGroup;

  /// The `CODECS` the playlist declares, lower-cased; null when it names none.
  final String? codecs;

  /// Whether the picture and sound are ones an MP4 can be written from on any
  /// device: H.264 with AAC. A stream often lists each size again with
  /// Dolby sound or HEVC, which the platform's muxer refuses. A playlist that
  /// declares no codecs is given the benefit of the doubt.
  bool get joinsAnywhere {
    final declared = codecs;
    if (declared == null || declared.isEmpty) return true;
    final parts = declared.split(',').map((part) => part.trim());
    return parts.every(
      (part) => part.startsWith('avc1') || part.startsWith('mp4a'),
    );
  }

  /// The side a quality is named after: a vertical 720x1280 video is 720p.
  int? get shortSide {
    final w = width, h = height;
    if (w == null || h == null) return h ?? w;
    return w < h ? w : h;
  }
}

/// A master playlist: the qualities on offer and where their sound is.
class HlsMaster {
  const HlsMaster({required this.variants, required this.audio});

  final List<HlsVariant> variants;

  /// Audio playlist URL by group id. A group whose sound is inside the video
  /// segments has no URL and so no entry.
  final Map<String, String> audio;
}

/// A stretch of one file, for playlists that address segments by byte range.
typedef HlsByteRange = ({int start, int length});

/// The key a segment is encrypted with, as `METHOD=AES-128` names it: a
/// 16-byte file at [uri], fetched like any other part of the stream.
class HlsKey {
  const HlsKey(this.uri, {this.initializationVector});

  final String uri;

  /// The 16 bytes the playlist gives, or null when it gives none and the
  /// segment's place in the stream stands in for them.
  final List<int>? initializationVector;
}

class HlsSegment {
  const HlsSegment(this.url, {this.range, this.key, this.sequence = 0});

  final String url;
  final HlsByteRange? range;

  /// Null for a segment served as it is.
  final HlsKey? key;

  /// The segment's media sequence number.
  final int sequence;

  /// What to initialise the cipher with: the playlist's own vector, or the
  /// sequence number as a 128-bit big-endian integer.
  List<int> get initializationVector {
    final given = key?.initializationVector;
    if (given != null) return given;
    final bytes = List<int>.filled(16, 0);
    var value = sequence;
    for (var index = 15; index >= 0 && value > 0; index--) {
      bytes[index] = value & 0xff;
      value >>= 8;
    }
    return bytes;
  }
}

/// A media playlist: the segments of one quality, in playing order.
class HlsMedia {
  const HlsMedia({
    required this.segments,
    required this.isComplete,
    required this.isEncrypted,
    this.initialization,
    this.duration = Duration.zero,
  });

  final List<HlsSegment> segments;

  /// The header fragmented-MP4 segments need in front of them. Null for
  /// MPEG-TS, whose segments stand alone.
  final HlsSegment? initialization;

  /// False for a live stream: its playlist has no end and keeps growing.
  final bool isComplete;

  /// True when segments are protected in a way that cannot be undone here:
  /// anything other than `AES-128` with a key at a web address. Sample
  /// encryption and the key systems of a DRM are of this kind.
  final bool isEncrypted;

  /// True when some segment has to be decrypted with a key the playlist names.
  bool get needsKey =>
      initialization?.key != null ||
      segments.any((segment) => segment.key != null);

  final Duration duration;
}

final RegExp _attribute = RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)');

Map<String, String> _attributes(String line) {
  final colon = line.indexOf(':');
  if (colon < 0) return const {};
  return {
    for (final match in _attribute.allMatches(line.substring(colon + 1)))
      match.group(1)!: _unquote(match.group(2)!),
  };
}

String _unquote(String value) =>
    value.length >= 2 && value.startsWith('"') && value.endsWith('"')
    ? value.substring(1, value.length - 1)
    : value;

/// `0x` and 32 hexadecimal digits, as an `IV` attribute is written.
List<int>? _hexBytes(String? value) {
  if (value == null) return null;
  final digits = value.toLowerCase().startsWith('0x')
      ? value.substring(2)
      : value;
  if (digits.length != 32) return null;
  final bytes = <int>[];
  for (var index = 0; index < 32; index += 2) {
    final byte = int.tryParse(digits.substring(index, index + 2), radix: 16);
    if (byte == null) return null;
    bytes.add(byte);
  }
  return bytes;
}

Iterable<String> _lines(String playlist) => playlist
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty);

/// True when [playlist] lists qualities rather than segments.
bool isHlsMaster(String playlist) => playlist.contains('#EXT-X-STREAM-INF');

/// Reads a master playlist fetched from [base]. Variants come back best first.
HlsMaster parseHlsMaster(String playlist, Uri base) {
  final variants = <HlsVariant>[];
  final audio = <String, String>{};
  Map<String, String>? pending;

  for (final line in _lines(playlist)) {
    if (line.startsWith('#EXT-X-MEDIA:')) {
      final attributes = _attributes(line);
      final group = attributes['GROUP-ID'];
      final uri = attributes['URI'];
      if (attributes['TYPE'] != 'AUDIO' || group == null || uri == null) {
        continue;
      }
      // The default language of a group wins; otherwise the first listed.
      if (attributes['DEFAULT'] == 'YES' || !audio.containsKey(group)) {
        audio[group] = base.resolve(uri).toString();
      }
    } else if (line.startsWith('#EXT-X-STREAM-INF:')) {
      pending = _attributes(line);
    } else if (!line.startsWith('#') && pending != null) {
      final resolution = (pending['RESOLUTION'] ?? '').toLowerCase().split('x');
      variants.add(
        HlsVariant(
          url: base.resolve(line).toString(),
          bandwidth: int.tryParse(pending['BANDWIDTH'] ?? '') ?? 0,
          width: resolution.length == 2 ? int.tryParse(resolution[0]) : null,
          height: resolution.length == 2 ? int.tryParse(resolution[1]) : null,
          audioGroup: pending['AUDIO'],
          codecs: pending['CODECS']?.toLowerCase(),
        ),
      );
      pending = null;
    }
  }

  variants.sort((a, b) {
    final bySize = (b.shortSide ?? 0).compareTo(a.shortSide ?? 0);
    return bySize != 0 ? bySize : b.bandwidth.compareTo(a.bandwidth);
  });
  return HlsMaster(variants: variants, audio: audio);
}

/// Reads a media playlist fetched from [base].
HlsMedia parseHlsMedia(String playlist, Uri base) {
  final segments = <HlsSegment>[];
  HlsSegment? initialization;
  HlsByteRange? pendingRange;
  HlsKey? key;
  var sequence = 0;
  var nextRangeStart = 0;
  var encrypted = false;
  var complete = false;
  var microseconds = 0;

  HlsByteRange rangeOf(String value) {
    // `<length>[@<start>]`; without a start it follows the previous range.
    final parts = value.split('@');
    final length = int.tryParse(parts[0]) ?? 0;
    final start = parts.length > 1
        ? int.tryParse(parts[1]) ?? 0
        : nextRangeStart;
    nextRangeStart = start + length;
    return (start: start, length: length);
  }

  for (final line in _lines(playlist)) {
    if (line.startsWith('#EXT-X-KEY:')) {
      // In force for every segment after it, until the next one.
      final attributes = _attributes(line);
      final method = attributes['METHOD'] ?? 'NONE';
      final address = Uri.tryParse(attributes['URI'] ?? '');
      final resolved = address == null ? null : base.resolveUri(address);
      if (method == 'NONE') {
        key = null;
      } else if (method == 'AES-128' &&
          resolved != null &&
          (resolved.scheme == 'http' || resolved.scheme == 'https')) {
        key = HlsKey(
          resolved.toString(),
          initializationVector: _hexBytes(attributes['IV']),
        );
      } else {
        encrypted = true;
      }
    } else if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
      sequence =
          int.tryParse(line.substring('#EXT-X-MEDIA-SEQUENCE:'.length)) ?? 0;
    } else if (line.startsWith('#EXT-X-MAP:')) {
      final attributes = _attributes(line);
      final uri = attributes['URI'];
      if (uri == null) continue;
      final range = attributes['BYTERANGE'];
      initialization = HlsSegment(
        base.resolve(uri).toString(),
        range: range == null ? null : rangeOf(range),
        key: key,
        sequence: sequence,
      );
    } else if (line.startsWith('#EXT-X-BYTERANGE:')) {
      pendingRange = rangeOf(line.substring('#EXT-X-BYTERANGE:'.length));
    } else if (line.startsWith('#EXTINF:')) {
      final seconds = double.tryParse(
        line.substring('#EXTINF:'.length).split(',').first,
      );
      if (seconds != null) microseconds += (seconds * 1e6).round();
    } else if (line.startsWith('#EXT-X-ENDLIST')) {
      complete = true;
    } else if (!line.startsWith('#')) {
      segments.add(
        HlsSegment(
          base.resolve(line).toString(),
          range: pendingRange,
          key: key,
          sequence: sequence,
        ),
      );
      sequence++;
      pendingRange = null;
    }
  }

  return HlsMedia(
    segments: segments,
    initialization: initialization,
    isComplete: complete,
    isEncrypted: encrypted,
    duration: Duration(microseconds: microseconds),
  );
}
