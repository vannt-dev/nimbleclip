class InstagramPageParser {
  const InstagramPageParser();

  String? firstGroup(String html, List<RegExp> patterns) {
    for (final pattern in patterns) {
      final value = pattern.firstMatch(html)?.group(1);
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  int? intField(String html, String key) {
    final match =
        RegExp('"$key":\\{?"?count"?:?\\s*(\\d+)').firstMatch(html) ??
        RegExp('"$key":(\\d+)').firstMatch(html);
    return int.tryParse(match?.group(1) ?? '');
  }

  int? durationSeconds(String html) {
    final value = RegExp(
      r'"video_duration":([\d.]+)',
    ).firstMatch(html)?.group(1);
    return double.tryParse(value ?? '')?.round();
  }
}
