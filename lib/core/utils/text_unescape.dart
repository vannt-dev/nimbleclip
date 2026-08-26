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

final _numericEntity = RegExp(r'&#([xX][0-9a-fA-F]+|[0-9]+);');

/// Decodes the handful of named HTML entities that show up in `<title>` and
/// `og:` meta tags, plus every numeric entity. Full named-entity decoding is
/// not worth a dependency here, but the numeric form has to be general:
/// Instagram and Facebook titles routinely carry `&#x2026;` and `&#8230;`.
String decodeHtmlEntities(String input) {
  if (!input.contains('&')) return input;
  return input
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .replaceAllMapped(_numericEntity, (match) {
        final token = match.group(1)!;
        final isHex = token.startsWith('x') || token.startsWith('X');
        final code = isHex
            ? int.tryParse(token.substring(1), radix: 16)
            : int.tryParse(token);
        // Out-of-range or unparsable values stay as written rather than
        // throwing from String.fromCharCode.
        if (code == null || code < 0 || code > 0x10FFFF) return match.group(0)!;
        return String.fromCharCode(code);
      })
      // Last, so that `&amp;#39;` decodes to the literal text `&#39;`.
      .replaceAll('&amp;', '&');
}
