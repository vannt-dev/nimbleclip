import 'package:xml/xml.dart';

import '../hls/hls_playlist.dart';

/// One encoding of the picture or the sound, as a manifest lists it.
class DashRepresentation {
  const DashRepresentation({
    required this.id,
    required this.isAudio,
    required this.bandwidth,
    required this.media,
    this.set = 0,
    this.width,
    this.height,
    this.codecs,
  });

  final String id;
  final bool isAudio;
  final int bandwidth;

  /// Which adaptation set it belongs to, counted in manifest order. For
  /// sound, each language is a set of its own.
  final int set;
  final int? width;
  final int? height;

  /// The `codecs` the manifest declares, lower-cased; null when it names none.
  final String? codecs;

  /// Its segments in playing order, in the shape the segment fetcher takes.
  final HlsMedia media;

  /// The side a quality is named after: a vertical 720x1280 video is 720p.
  int? get shortSide {
    final w = width, h = height;
    if (w == null || h == null) return h ?? w;
    return w < h ? w : h;
  }

  /// Whether this is an encoding an MP4 can be written from on any device:
  /// H.264 picture or AAC sound. A manifest that declares no codecs is given
  /// the benefit of the doubt.
  bool get joinsAnywhere {
    final declared = codecs;
    if (declared == null || declared.isEmpty) return true;
    return declared
        .split(',')
        .map((part) => part.trim())
        .every((part) => part.startsWith('avc1') || part.startsWith('mp4a'));
  }
}

/// A manifest: every encoding of the picture and of the sound.
class DashManifest {
  const DashManifest({
    required this.videos,
    required this.audio,
    required this.isLive,
    required this.isProtected,
    required this.isSinglePeriod,
    this.duration,
  });

  /// Best first: by size, then bitrate.
  final List<DashRepresentation> videos;

  /// Best first: AAC before anything else, then the language the manifest
  /// lists first - what a player with no preference plays - then bitrate.
  final List<DashRepresentation> audio;

  /// True for a broadcast still going on: the manifest keeps growing.
  final bool isLive;

  /// True when the content is under a key system (`ContentProtection`).
  final bool isProtected;

  /// False when the manifest is cut into several periods, which would have to
  /// be joined end to end; only the first is read.
  final bool isSinglePeriod;

  final Duration? duration;

  DashRepresentation? byId(String id) {
    for (final representation in [...videos, ...audio]) {
      if (representation.id == id) return representation;
    }
    return null;
  }
}

/// Reads the manifest [xml] fetched from [base].
///
/// Throws a [FormatException] when it is not a DASH manifest.
DashManifest parseDashManifest(String xml, Uri base) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(xml);
  } on XmlException catch (error) {
    throw FormatException('not a DASH manifest: ${error.message}');
  }
  final root = document.rootElement;
  if (root.name.local != 'MPD') {
    throw const FormatException('not a DASH manifest: no MPD element');
  }

  final periods = _children(root, 'Period').toList();
  final isLive = root.getAttribute('type') == 'dynamic';
  final total = _duration(root.getAttribute('mediaPresentationDuration'));
  final videos = <DashRepresentation>[];
  final audio = <DashRepresentation>[];
  var protected = false;

  if (periods.isNotEmpty) {
    final period = periods.first;
    final periodBase = _baseOf(period, _baseOf(root, base));
    final length = _duration(period.getAttribute('duration')) ?? total;

    final sets = _children(period, 'AdaptationSet').toList();
    for (var setIndex = 0; setIndex < sets.length; setIndex++) {
      final set = sets[setIndex];
      final setBase = _baseOf(set, periodBase);
      if (_children(set, 'ContentProtection').isNotEmpty) protected = true;

      for (final representation in _children(set, 'Representation')) {
        if (_children(representation, 'ContentProtection').isNotEmpty) {
          protected = true;
        }
        String? inherited(String name) =>
            representation.getAttribute(name) ?? set.getAttribute(name);

        final type =
            (inherited('contentType') ??
                    inherited('mimeType')?.split('/').first ??
                    '')
                .toLowerCase();
        if (type != 'video' && type != 'audio') continue;
        final id = representation.getAttribute('id');
        if (id == null || id.isEmpty) continue;
        final bandwidth =
            int.tryParse(representation.getAttribute('bandwidth') ?? '') ?? 0;

        final media = _segmentsOf(
          [representation, set, period],
          _baseOf(representation, setBase),
          id: id,
          bandwidth: bandwidth,
          length: length,
          isLive: isLive,
        );
        if (media == null) continue;

        (type == 'audio' ? audio : videos).add(
          DashRepresentation(
            id: id,
            isAudio: type == 'audio',
            bandwidth: bandwidth,
            set: setIndex,
            width: int.tryParse(inherited('width') ?? ''),
            height: int.tryParse(inherited('height') ?? ''),
            codecs: inherited('codecs')?.toLowerCase(),
            media: media,
          ),
        );
      }
    }
  }

  videos.sort((a, b) {
    final bySize = (b.shortSide ?? 0).compareTo(a.shortSide ?? 0);
    return bySize != 0 ? bySize : b.bandwidth.compareTo(a.bandwidth);
  });
  audio.sort((a, b) {
    if (a.joinsAnywhere != b.joinsAnywhere) return a.joinsAnywhere ? -1 : 1;
    if (a.set != b.set) return a.set.compareTo(b.set);
    return b.bandwidth.compareTo(a.bandwidth);
  });

  return DashManifest(
    videos: videos,
    audio: audio,
    isLive: isLive,
    isProtected: protected,
    isSinglePeriod: periods.length <= 1,
    duration: _overallDuration(periods, total),
  );
}

/// The length the manifest gives for the whole, or for its first period.
Duration? _overallDuration(List<XmlElement> periods, Duration? total) =>
    total ??
    (periods.isEmpty
        ? null
        : _duration(periods.first.getAttribute('duration')));

Iterable<XmlElement> _children(XmlElement parent, String name) =>
    parent.childElements.where((element) => element.name.local == name);

XmlElement? _child(XmlElement parent, String name) {
  for (final element in _children(parent, name)) {
    return element;
  }
  return null;
}

/// [parent]'s own `BaseURL` resolved against [inherited], or [inherited].
Uri _baseOf(XmlElement parent, Uri inherited) {
  final text = _child(parent, 'BaseURL')?.innerText.trim() ?? '';
  if (text.isEmpty) return inherited;
  try {
    return inherited.resolve(text);
  } on FormatException {
    return inherited;
  }
}

final RegExp _iso8601 = RegExp(
  r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$',
);

/// `PT1H2M3.5S`, as a manifest writes a length.
Duration? _duration(String? value) {
  final match = _iso8601.firstMatch(value?.trim() ?? '');
  if (match == null) return null;
  final seconds = double.tryParse(match.group(4) ?? '0') ?? 0;
  return Duration(
    days: int.parse(match.group(1) ?? '0'),
    hours: int.parse(match.group(2) ?? '0'),
    minutes: int.parse(match.group(3) ?? '0'),
    microseconds: (seconds * 1e6).round(),
  );
}

/// `<start>-<end>`, both inclusive, as a manifest writes a byte range.
HlsByteRange? _range(String? value) {
  final parts = value?.split('-');
  if (parts == null || parts.length != 2) return null;
  final start = int.tryParse(parts[0]);
  final end = int.tryParse(parts[1]);
  if (start == null || end == null || end < start) return null;
  return (start: start, length: end - start + 1);
}

/// The segments of one representation.
///
/// [levels] are the elements that may describe them, nearest first: the
/// representation, its adaptation set, its period. Null when they are
/// described in a way that cannot be turned into a list.
HlsMedia? _segmentsOf(
  List<XmlElement> levels,
  Uri base, {
  required String id,
  required int bandwidth,
  required Duration? length,
  required bool isLive,
}) {
  HlsMedia media(List<HlsSegment> segments, HlsSegment? initialization) =>
      HlsMedia(
        segments: segments,
        initialization: initialization,
        isComplete: !isLive,
        isEncrypted: false,
        duration: length ?? Duration.zero,
      );

  // A template: addresses built from a pattern and a count or a timeline.
  final templates = [
    for (final level in levels) ?_child(level, 'SegmentTemplate'),
  ];
  if (templates.isNotEmpty) {
    // The nearest level wins attribute by attribute; a representation often
    // repeats only what differs from its adaptation set.
    String? attribute(String name) {
      for (final template in templates) {
        final value = template.getAttribute(name);
        if (value != null) return value;
      }
      return null;
    }

    final pattern = attribute('media');
    if (pattern == null) return null;
    final timescale = int.tryParse(attribute('timescale') ?? '') ?? 1;
    var number = int.tryParse(attribute('startNumber') ?? '') ?? 1;

    String address(String template, {int? number, int? time}) => base
        .resolve(
          _fill(
            template,
            id: id,
            bandwidth: bandwidth,
            number: number,
            time: time,
          ),
        )
        .toString();

    final initialization = attribute('initialization');
    final header = initialization == null
        ? null
        : HlsSegment(address(initialization));

    final segments = <HlsSegment>[];
    XmlElement? timeline;
    for (final template in templates) {
      timeline = _child(template, 'SegmentTimeline');
      if (timeline != null) break;
    }

    if (timeline != null) {
      var time = 0;
      final entries = _children(timeline, 'S').toList();
      for (var index = 0; index < entries.length; index++) {
        final entry = entries[index];
        final duration = int.tryParse(entry.getAttribute('d') ?? '');
        if (duration == null || duration <= 0) return null;
        time = int.tryParse(entry.getAttribute('t') ?? '') ?? time;
        var repeat = int.tryParse(entry.getAttribute('r') ?? '') ?? 0;
        if (repeat < 0) {
          // "Until the next entry, or the end": needs an end to count to.
          final next = index + 1 < entries.length
              ? int.tryParse(entries[index + 1].getAttribute('t') ?? '')
              : null;
          final end =
              next ??
              (length == null
                  ? null
                  : (length.inMicroseconds * timescale / 1e6).round());
          if (end == null) return null;
          repeat = ((end - time) / duration).ceil() - 1;
        }
        for (var count = 0; count <= repeat; count++) {
          segments.add(
            HlsSegment(address(pattern, number: number, time: time)),
          );
          number++;
          time += duration;
        }
      }
    } else {
      final duration = int.tryParse(attribute('duration') ?? '');
      if (duration == null || duration <= 0 || length == null) return null;
      final count = (length.inMicroseconds * timescale / 1e6 / duration).ceil();
      for (var index = 0; index < count; index++) {
        segments.add(HlsSegment(address(pattern, number: number + index)));
      }
    }
    return segments.isEmpty ? null : media(segments, header);
  }

  // A list: every address written out.
  for (final level in levels) {
    final list = _child(level, 'SegmentList');
    if (list == null) continue;
    final initialization = _child(list, 'Initialization');
    final source = initialization?.getAttribute('sourceURL');
    final range = _range(initialization?.getAttribute('range'));
    final header = initialization == null || (source == null && range == null)
        ? null
        : HlsSegment(
            source == null ? base.toString() : base.resolve(source).toString(),
            range: range,
          );
    final segments = [
      for (final entry in _children(list, 'SegmentURL'))
        HlsSegment(
          entry.getAttribute('media') == null
              ? base.toString()
              : base.resolve(entry.getAttribute('media')!).toString(),
          range: _range(entry.getAttribute('mediaRange')),
        ),
    ];
    return segments.isEmpty ? null : media(segments, header);
  }

  // Neither: the representation is one file at its base address, indexed
  // inside itself. It is fetched whole.
  if (base.path.isEmpty || base.path.endsWith('/')) return null;
  return media([HlsSegment(base.toString())], null);
}

final RegExp _placeholder = RegExp(
  r'\$(RepresentationID|Number|Bandwidth|Time)?(?:%0(\d+)d)?\$',
);

/// Fills `$Number$`, `$Time$`, `$RepresentationID$`, `$Bandwidth$` (with an
/// optional `%0Nd` width) and `$$` in a segment address pattern.
String _fill(
  String template, {
  required String id,
  required int bandwidth,
  int? number,
  int? time,
}) => template.replaceAllMapped(_placeholder, (match) {
  final name = match.group(1);
  if (name == null) return r'$';
  if (name == 'RepresentationID') return id;
  final value = switch (name) {
    'Number' => number ?? 0,
    'Time' => time ?? 0,
    _ => bandwidth,
  };
  final width = int.tryParse(match.group(2) ?? '') ?? 1;
  return value.toString().padLeft(width, '0');
});
