import '../../models/video_metadata.dart';

class MediaInspection {
  const MediaInspection({required this.kind, required this.extension});

  final MediaKind kind;
  final String extension;
}

/// Identifies supported media from its bytes instead of trusting a URL or
/// Content-Type header, both of which frequently describe CDN error responses.
class MediaFileValidator {
  const MediaFileValidator();

  MediaInspection? inspect(List<int> bytes) {
    if (bytes.length < 4) return null;

    if (_startsWith(bytes, const [0xff, 0xd8, 0xff])) {
      return const MediaInspection(kind: MediaKind.image, extension: 'jpg');
    }
    if (_startsWith(bytes, const [0x89, 0x50, 0x4e, 0x47])) {
      return const MediaInspection(kind: MediaKind.image, extension: 'png');
    }
    if (_asciiAt(bytes, 0, 'GIF87a') || _asciiAt(bytes, 0, 'GIF89a')) {
      return const MediaInspection(kind: MediaKind.image, extension: 'gif');
    }
    if (_asciiAt(bytes, 0, 'RIFF') && _asciiAt(bytes, 8, 'WEBP')) {
      return const MediaInspection(kind: MediaKind.image, extension: 'webp');
    }

    if (_asciiAt(bytes, 4, 'ftyp')) {
      final brand = bytes.length >= 12
          ? String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase()
          : '';
      if (const {'avif', 'avis'}.contains(brand)) {
        return const MediaInspection(kind: MediaKind.image, extension: 'avif');
      }
      if (const {'heic', 'heix', 'hevc', 'hevx', 'mif1'}.contains(brand)) {
        return const MediaInspection(kind: MediaKind.image, extension: 'heic');
      }
      if (brand.startsWith('m4a') ||
          brand.startsWith('m4b') ||
          brand.startsWith('m4p')) {
        return const MediaInspection(kind: MediaKind.audio, extension: 'm4a');
      }
      return MediaInspection(
        kind: MediaKind.video,
        extension: brand == 'qt  ' ? 'mov' : 'mp4',
      );
    }
    if (_startsWith(bytes, const [0x1a, 0x45, 0xdf, 0xa3])) {
      return const MediaInspection(kind: MediaKind.video, extension: 'webm');
    }
    if (bytes.length > 376 &&
        bytes[0] == 0x47 &&
        bytes[188] == 0x47 &&
        bytes[376] == 0x47) {
      return const MediaInspection(kind: MediaKind.video, extension: 'ts');
    }

    if (_asciiAt(bytes, 0, 'ID3') || _looksLikeMp3Frame(bytes)) {
      return const MediaInspection(kind: MediaKind.audio, extension: 'mp3');
    }
    if (_asciiAt(bytes, 0, 'OggS')) {
      return const MediaInspection(kind: MediaKind.audio, extension: 'ogg');
    }
    if (_asciiAt(bytes, 0, 'fLaC')) {
      return const MediaInspection(kind: MediaKind.audio, extension: 'flac');
    }
    if (_asciiAt(bytes, 0, 'RIFF') && _asciiAt(bytes, 8, 'WAVE')) {
      return const MediaInspection(kind: MediaKind.audio, extension: 'wav');
    }
    if (_looksLikeAac(bytes)) {
      return const MediaInspection(kind: MediaKind.audio, extension: 'aac');
    }
    return null;
  }

  bool matchesExpectedKind(MediaInspection inspection, MediaKind expected) {
    // ISO-BMFF uses the same `ftyp` envelope for MP4 video and M4A audio. A
    // declared audio option is therefore allowed to reinterpret MP4 as M4A.
    if (expected == MediaKind.audio && inspection.extension == 'mp4') {
      return true;
    }
    return inspection.kind == expected;
  }

  String extensionFor(MediaInspection inspection, MediaKind expected) {
    if (inspection.kind == MediaKind.audio && inspection.extension == 'm4a') {
      return 'm4a';
    }
    if (expected == MediaKind.audio && inspection.extension == 'mp4') {
      return 'm4a';
    }
    return inspection.extension;
  }

  bool _startsWith(List<int> bytes, List<int> signature) {
    if (bytes.length < signature.length) return false;
    for (var index = 0; index < signature.length; index++) {
      if (bytes[index] != signature[index]) return false;
    }
    return true;
  }

  bool _asciiAt(List<int> bytes, int offset, String value) {
    if (bytes.length < offset + value.length) return false;
    for (var index = 0; index < value.length; index++) {
      if (bytes[offset + index] != value.codeUnitAt(index)) return false;
    }
    return true;
  }

  bool _looksLikeMp3Frame(List<int> bytes) =>
      bytes.length >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0;

  bool _looksLikeAac(List<int> bytes) =>
      bytes.length >= 2 && bytes[0] == 0xff && (bytes[1] & 0xf6) == 0xf0;
}
