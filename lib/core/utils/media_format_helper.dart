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
    final match = _fileExtensionInsensitive.firstMatch(path);
    final extension = _normalize(match?.group(1));
    if (extension != null && _imageFormats.contains(extension)) {
      return extension == 'jpeg' ? 'jpg' : extension;
    }
    return 'jpg';
  }

  static final RegExp _fileExtensionInsensitive = RegExp(
    r'\.([a-zA-Z0-9]+)$',
    caseSensitive: false,
  );
  static final RegExp _fileExtension = RegExp(r'\.([a-zA-Z0-9]+)$');

  static bool isImageUrl(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final extension = _normalize(_fileExtension.firstMatch(path)?.group(1));
    return extension != null && _imageFormats.contains(extension);
  }

  /// MIME types of the audio formats a download can arrive in or be converted
  /// to. Spelled out rather than asked of the platform, which files several of
  /// these extensions (`webm`, `mp4`, `ogg`) under video.
  static const _audioMimeTypes = {
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'mp4': 'audio/mp4',
    'aac': 'audio/aac',
    'ogg': 'audio/ogg',
    'oga': 'audio/ogg',
    'opus': 'audio/ogg',
    'webm': 'audio/webm',
    'weba': 'audio/webm',
    'wav': 'audio/x-wav',
    'flac': 'audio/flac',
  };

  /// The MIME type to file an audio download under in the device's music
  /// library, from its file name or path. Always an `audio/` type: the library
  /// refuses anything else, so an unknown extension is filed as plain MP3-style
  /// audio rather than left out.
  static String audioMimeType(String fileName) {
    final extension = _normalize(
      _fileExtensionInsensitive.firstMatch(fileName)?.group(1),
    );
    return _audioMimeTypes[extension] ?? 'audio/mpeg';
  }

  static String? _normalize(String? value) {
    final normalized = value?.replaceAll('.', '').trim().toLowerCase();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
