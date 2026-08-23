import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/core/utils/media_file_validator.dart';
import 'package:nimble_clip/models/video_metadata.dart';

void main() {
  const validator = MediaFileValidator();

  test('identifies MP4 from its ftyp box', () {
    final bytes = <int>[0, 0, 0, 24, ...'ftypisom'.codeUnits];
    final result = validator.inspect(bytes);

    expect(result?.kind, MediaKind.video);
    expect(result?.extension, 'mp4');
  });

  test('identifies common image and audio signatures', () {
    expect(validator.inspect(const [0xff, 0xd8, 0xff, 0xe0])?.extension, 'jpg');
    expect(
      validator.inspect(<int>[...'ID3'.codeUnits, 4, 0, 0])?.extension,
      'mp3',
    );
  });

  test('rejects markup and unknown octet-stream bytes', () {
    expect(validator.inspect('<html>expired</html>'.codeUnits), isNull);
    expect(validator.inspect(List<int>.filled(64, 0x42)), isNull);
  });

  test('treats an ISO-BMFF audio option as M4A', () {
    final inspection = validator.inspect(<int>[
      0,
      0,
      0,
      24,
      ...'ftypM4A '.codeUnits,
    ])!;

    expect(inspection.kind, MediaKind.audio);
    expect(validator.matchesExpectedKind(inspection, MediaKind.audio), isTrue);
    expect(validator.extensionFor(inspection, MediaKind.audio), 'm4a');
  });
}
