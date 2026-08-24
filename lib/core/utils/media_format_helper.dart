class MediaFormatHelper {
  MediaFormatHelper._();

  static const _imageFormats = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'avif',
    'bmp',
    'heic',
  };

  static String inferImageFormat(String url, {String? declaredFormat}) {
    final declared = _normalize(declaredFormat);
    if (declared != null && _imageFormats.contains(declared)) {
      return declared == 'jpeg' ? 'jpg' : declared;
    }

    final path = Uri.tryParse(url)?.path ?? url;
    final match = RegExp(
      r'\.([a-zA-Z0-9]+)$',
      caseSensitive: false,
    ).firstMatch(path);
    final extension = _normalize(match?.group(1));
    if (extension != null && _imageFormats.contains(extension)) {
      return extension == 'jpeg' ? 'jpg' : extension;
    }
    return 'jpg';
  }

  static bool isImageUrl(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final extension = _normalize(
      RegExp(r'\.([a-zA-Z0-9]+)$').firstMatch(path)?.group(1),
    );
    return extension != null && _imageFormats.contains(extension);
  }

  static String? _normalize(String? value) {
    final normalized = value?.replaceAll('.', '').trim().toLowerCase();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
