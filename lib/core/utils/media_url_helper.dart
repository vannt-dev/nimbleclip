import 'text_unescape.dart';

class MediaUrlHelper {
  MediaUrlHelper._();

  static String decode(String value) =>
      decodeHtmlEntities(decodeJsonEscapes(value));

  static bool isHttp(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }
}
