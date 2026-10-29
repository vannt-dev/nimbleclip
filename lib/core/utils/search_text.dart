/// Turns text into the form a search compares: lower case, without accents,
/// with single spaces.
///
/// People type Vietnamese without its marks as often as with them, so
/// "tieng viet" has to find "Tiếng Việt". Titles may also arrive with the
/// marks as separate combining characters rather than precomposed letters;
/// both forms fold to the same result.
String foldForSearch(String text) {
  final lower = text.toLowerCase();
  final out = StringBuffer();
  var pendingSpace = false;
  for (final rune in lower.runes) {
    // Combining diacritical marks.
    if (rune >= 0x0300 && rune <= 0x036F) continue;
    final char = String.fromCharCode(rune);
    if (char.trim().isEmpty) {
      pendingSpace = out.isNotEmpty;
      continue;
    }
    if (pendingSpace) {
      out.write(' ');
      pendingSpace = false;
    }
    out.write(_plain[char] ?? char);
  }
  return out.toString();
}

/// Each accented lower-case letter mapped to its plain letter.
final Map<String, String> _plain = () {
  const groups = {
    'a': 'àáảãạăằắẳẵặâầấẩẫậäåāą',
    'e': 'èéẻẽẹêềếểễệëēęě',
    'i': 'ìíỉĩịîïī',
    'o': 'òóỏõọôồốổỗộơờớởỡợöøō',
    'u': 'ùúủũụưừứửữựûüūů',
    'y': 'ỳýỷỹỵÿ',
    'd': 'đď',
    'c': 'çćč',
    'n': 'ñńň',
    's': 'śšş',
    'z': 'źżž',
    'r': 'ř',
    't': 'ť',
    'l': 'ł',
  };
  final map = <String, String>{};
  groups.forEach((plain, accented) {
    for (final rune in accented.runes) {
      map[String.fromCharCode(rune)] = plain;
    }
  });
  return map;
}();
