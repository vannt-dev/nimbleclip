/// Decodes the backslash escapes that Facebook and Instagram embed in the inline
/// JSON blobs of their pages (`\/`, `\uXXXX`, `\"`, ...).
///
/// These blobs are pulled out of the page HTML with a regex rather than a JSON
/// parser, so the escapes arrive verbatim. Stripping backslashes wholesale would
/// turn `é` into `u00e9`, so each escape is decoded in a single pass.
String decodeJsonEscapes(String input) {
  if (!input.contains(r'\')) return input;

  final buffer = StringBuffer();
  var i = 0;
  while (i < input.length) {
    final char = input[i];
    if (char != r'\' || i + 1 >= input.length) {
      buffer.write(char);
      i++;
      continue;
    }

    final next = input[i + 1];
    switch (next) {
      case 'u':
        final code = i + 6 <= input.length
            ? int.tryParse(input.substring(i + 2, i + 6), radix: 16)
            : null;
        if (code != null) {
          buffer.writeCharCode(code);
          i += 6;
        } else {
          buffer.write(next);
          i += 2;
        }
      case 'n':
        buffer.write('\n');
        i += 2;
      case 'r':
        buffer.write('\r');
        i += 2;
      case 't':
        buffer.write('\t');
        i += 2;
      case 'b':
        buffer.writeCharCode(0x08);
        i += 2;
      case 'f':
        buffer.writeCharCode(0x0c);
        i += 2;
      default:
        // Covers `\/`, `\"`, `\\` and any stray escape: keep the literal char.
        buffer.write(next);
        i += 2;
    }
  }
  return buffer.toString();
}

const _namedEntities = <String, String>{
  'quot': '"',
  'apos': "'",
  'lt': '<',
  'gt': '>',
  'nbsp': ' ',
  'amp': '&',
};

/// Decodes the handful of named HTML entities that show up in `<title>` and
/// `og:` meta tags, plus every numeric entity. Full named-entity decoding is
/// not worth a dependency here, but the numeric form has to be general:
/// Instagram and Facebook titles routinely carry `&#x2026;` and `&#8230;`.
///
/// One pass, one buffer. The earlier version chained five `replaceAll` calls, a
/// `replaceAllMapped` and a final `replaceAll`, which copied the whole string
/// seven times. That is invisible on a title but not on the multi-megabyte
/// `<script type="application/json">` payloads the Facebook parser feeds it.
///
/// Decoding each entity where it is found also removes the ordering trick the
/// chained version depended on — `&amp;` had to be resolved last so that
/// `&amp;#39;` stayed the literal text `&#39;`. Here the `&amp;` is consumed
/// and the rest is copied verbatim, which gives the same answer directly.
String decodeHtmlEntities(String input) {
  var cursor = input.indexOf('&');
  if (cursor < 0) return input;

  final buffer = StringBuffer()..write(input.substring(0, cursor));
  while (cursor < input.length) {
    if (input.codeUnitAt(cursor) != 0x26 /* & */ ) {
      // Copy the whole run up to the next candidate in one slice rather than
      // one code unit at a time.
      final next = input.indexOf('&', cursor);
      if (next < 0) {
        buffer.write(input.substring(cursor));
        break;
      }
      buffer.write(input.substring(cursor, next));
      cursor = next;
      continue;
    }

    // Scan the token without allocating: an entity body is alphanumeric, with
    // an optional leading `#`. A bare `&` in a query string stops on its very
    // next character, so URLs cost nothing here.
    var end = cursor + 1;
    while (end < input.length) {
      final unit = input.codeUnitAt(end);
      final isTokenChar =
          (unit >= 0x30 && unit <= 0x39) || // 0-9
          (unit >= 0x41 && unit <= 0x5a) || // A-Z
          (unit >= 0x61 && unit <= 0x7a) || // a-z
          (unit == 0x23 /* # */ && end == cursor + 1);
      if (!isTokenChar) break;
      end++;
    }

    final decoded =
        end > cursor + 1 &&
            end < input.length &&
            input.codeUnitAt(end) == 0x3b /* ; */
        ? _decodeEntityToken(input.substring(cursor + 1, end))
        : null;
    if (decoded == null) {
      buffer.writeCharCode(0x26);
      cursor++;
      continue;
    }
    buffer.write(decoded);
    cursor = end + 1;
  }
  return buffer.toString();
}

/// Resolves the text between `&` and `;`, or null when it is not an entity this
/// decoder knows. Out-of-range and unparsable numeric values return null so the
/// original text is preserved rather than throwing from `String.fromCharCode`.
String? _decodeEntityToken(String token) {
  if (!token.startsWith('#')) return _namedEntities[token];

  final body = token.substring(1);
  if (body.isEmpty) return null;
  final isHex = body.startsWith('x') || body.startsWith('X');
  final digits = isHex ? body.substring(1) : body;
  if (digits.isEmpty) return null;
  final code = isHex ? int.tryParse(digits, radix: 16) : int.tryParse(digits);
  if (code == null || code < 0 || code > 0x10FFFF) return null;
  return String.fromCharCode(code);
}
