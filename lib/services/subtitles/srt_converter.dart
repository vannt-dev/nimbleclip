/// Turns WebVTT subtitles into SubRip (`.srt`), the format video players and
/// editors read beside a video file.
///
/// Speech-recognised subtitles are served as rolling captions: each cue
/// repeats the line before it and times every word, and a cue of a few
/// milliseconds holds the text between two lines. Written out as they are,
/// every line would show twice. Those repeats are dropped, so each line is
/// shown once, from when it is spoken until the next one starts.
String webVttToSrt(String webVtt) {
  final cues = _parse(webVtt);
  final rolling = _wordTiming.hasMatch(webVtt);
  final kept = rolling ? _collapseRolling(cues) : cues;
  final out = StringBuffer();
  var number = 0;
  for (final cue in kept) {
    if (cue.lines.isEmpty) continue;
    number++;
    out
      ..writeln(number)
      ..writeln('${_srtTime(cue.start)} --> ${_srtTime(cue.end)}')
      ..writeln(cue.lines.join('\n'))
      ..writeln();
  }
  return out.toString();
}

class _Cue {
  _Cue(this.start, this.end, this.lines);

  final Duration start;
  Duration end;
  final List<String> lines;
}

final RegExp _timing = RegExp(
  r'^((?:\d+:)?\d{1,2}:\d{2}[.,]\d{1,3})\s+-->\s+((?:\d+:)?\d{1,2}:\d{2}[.,]\d{1,3})',
);
final RegExp _wordTiming = RegExp(r'<\d+:\d{2}(?::\d{2})?[.,]\d{3}>');
final RegExp _tag = RegExp(r'<[^>]*>');

/// SubRip players understand these; every other tag is WebVTT's own.
const _keptTags = {'b', 'i', 'u', '/b', '/i', '/u'};

List<_Cue> _parse(String webVtt) {
  final lines = webVtt
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  final cues = <_Cue>[];
  var index = 0;
  while (index < lines.length) {
    final match = _timing.firstMatch(lines[index].trim());
    if (match == null) {
      // The header, a cue's name, a NOTE, STYLE or REGION block: skipped
      // up to the next timing line.
      index++;
      continue;
    }
    final start = _parseTime(match.group(1)!);
    final end = _parseTime(match.group(2)!);
    index++;
    final text = <String>[];
    // A cue ends at an empty line. A line of spaces is part of it: rolling
    // captions open with one.
    while (index < lines.length &&
        lines[index].isNotEmpty &&
        !_timing.hasMatch(lines[index].trim())) {
      final line = _cleanLine(lines[index]);
      if (line.isNotEmpty) text.add(line);
      index++;
    }
    if (start != null && end != null && end > start) {
      cues.add(_Cue(start, end, text));
    }
  }
  return cues;
}

String _cleanLine(String line) {
  final withoutTags = line.replaceAllMapped(_tag, (match) {
    final name = match.group(0)!;
    final inner = name.substring(1, name.length - 1).trim().toLowerCase();
    return _keptTags.contains(inner) ? '<$inner>' : '';
  });
  return withoutTags
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lrm;', '')
      .replaceAll('&rlm;', '')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Keeps of each cue only the lines the one before did not already show,
/// and drops a cue left with nothing new.
List<_Cue> _collapseRolling(List<_Cue> cues) {
  final kept = <_Cue>[];
  var shown = const <String>[];
  for (final cue in cues) {
    var lines = cue.lines;
    // The longest run of this cue's first lines that ends what was shown.
    for (var overlap = lines.length; overlap > 0; overlap--) {
      if (overlap > shown.length) continue;
      final tail = shown.sublist(shown.length - overlap);
      final head = lines.sublist(0, overlap);
      if (_sameLines(tail, head)) {
        lines = lines.sublist(overlap);
        break;
      }
    }
    if (cue.lines.isNotEmpty) shown = cue.lines;
    if (lines.isEmpty) continue;
    // The line before stays up until this one starts, not a moment more.
    if (kept.isNotEmpty && kept.last.end > cue.start) {
      kept.last.end = cue.start;
    }
    kept.add(_Cue(cue.start, cue.end, lines));
  }
  return kept;
}

bool _sameLines(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Duration? _parseTime(String text) {
  final parts = text.replaceAll(',', '.').split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  final hours = parts.length == 3 ? int.tryParse(parts[0]) : 0;
  final minutes = int.tryParse(parts[parts.length - 2]);
  final secondsParts = parts.last.split('.');
  final seconds = int.tryParse(secondsParts.first);
  final fraction = secondsParts.length > 1 ? secondsParts[1] : '0';
  final millis = int.tryParse(fraction.padRight(3, '0').substring(0, 3));
  if (hours == null || minutes == null || seconds == null || millis == null) {
    return null;
  }
  return Duration(
    hours: hours,
    minutes: minutes,
    seconds: seconds,
    milliseconds: millis,
  );
}

String _srtTime(Duration time) {
  String two(int value) => value.toString().padLeft(2, '0');
  final hours = time.inHours;
  final minutes = time.inMinutes.remainder(60);
  final seconds = time.inSeconds.remainder(60);
  final millis = time.inMilliseconds.remainder(1000);
  return '${two(hours)}:${two(minutes)}:${two(seconds)},'
      '${millis.toString().padLeft(3, '0')}';
}
