/// Extracts the balanced `{...}` object that starts at the first `{` at or after
/// [startIndex], honouring string literals and escapes.
///
/// A non-greedy `({.+?})` regex truncates at the first `}` that happens to be
/// followed by the delimiter, which corrupts blobs like YouTube's
/// `ytInitialPlayerResponse` whenever a nested object or a string containing
/// `};` appears before the real end.
String? extractBalancedJson(String source, int startIndex) {
  final open = source.indexOf('{', startIndex);
  if (open < 0) return null;

  var depth = 0;
  var inString = false;
  var escaped = false;

  for (var i = open; i < source.length; i++) {
    final char = source.codeUnitAt(i);

    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char == 0x5c /* \ */ ) {
        escaped = true;
      } else if (char == 0x22 /* " */ ) {
        inString = false;
      }
      continue;
    }

    switch (char) {
      case 0x22: // "
        inString = true;
      case 0x7b: // {
        depth++;
      case 0x7d: // }
        depth--;
        if (depth == 0) return source.substring(open, i + 1);
    }
  }
  return null;
}

/// Finds [marker] in [source] and returns the balanced JSON object that follows
/// it, or null when the marker is absent or the object never closes.
String? extractJsonAfterMarker(String source, String marker) {
  final index = source.indexOf(marker);
  if (index < 0) return null;
  return extractBalancedJson(source, index + marker.length);
}
