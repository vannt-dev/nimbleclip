class InstagramPageParser {
  const InstagramPageParser();

  String? firstGroup(String html, List<RegExp> patterns) {
    for (final pattern in patterns) {
      final value = pattern.firstMatch(html)?.group(1);
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  /// `intField` builds its patterns from the caller's key, so they cannot be
  /// plain statics. The keys come from a small fixed set of call sites, so
  /// caching by key compiles each expression once per process instead of once
  /// per extraction.
  static final Map<String, RegExp> _countPatterns = {};
  static final Map<String, RegExp> _plainPatterns = {};
  static final RegExp _videoDuration = RegExp(r'"video_duration":([\d.]+)');

  int? intField(String html, String key) {
    final countPattern = _countPatterns.putIfAbsent(
      key,
      () => RegExp('"$key":\\{?"?count"?:?\\s*(\\d+)'),
    );
    final plainPattern = _plainPatterns.putIfAbsent(
      key,
      () => RegExp('"$key":(\\d+)'),
    );
    final match =
        countPattern.firstMatch(html) ?? plainPattern.firstMatch(html);
    return int.tryParse(match?.group(1) ?? '');
  }

  int? durationSeconds(String html) {
    final value = _videoDuration.firstMatch(html)?.group(1);
    return double.tryParse(value ?? '')?.round();
  }
}
