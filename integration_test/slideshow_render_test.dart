import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// On-device checks for the native slideshow encoder.
///
/// Task 8 is picture only: the encoder must turn local image files into a
/// playable silent MP4 and report `audioSkipped` unconditionally. Audio
/// muxing arrives in Task 9, which reuses the `probe` method added here.
///
///   flutter test integration_test/slideshow_render_test.dart -d emulator-5554
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.vannt.nimbleclip/slideshow');

  /// Deliberately mismatched sizes and aspect ratios: a square, a landscape
  /// frame wider than 9:16, and a portrait frame taller than it. Uniform
  /// fixtures would never exercise the fit-plus-blurred-background compositing.
  const sizes = <List<int>>[
    [400, 400],
    [800, 450],
    [300, 900],
  ];
  const colors = <int>[0xFFE53935, 0xFF1E88E5, 0xFF43A047];

  Future<List<String>> writeFixtures(Directory dir) async {
    final paths = <String>[];
    for (var i = 0; i < sizes.length; i++) {
      final file = File('${dir.path}/frame_$i.png');
      await file.writeAsBytes(
        await _solidPng(sizes[i][0], sizes[i][1], colors[i]),
      );
      paths.add(file.path);
    }
    return paths;
  }

  test('three images become one playable mp4', () async {
    final dir = await getTemporaryDirectory();
    final paths = await writeFixtures(dir);
    final out = '${dir.path}/out.mp4';
    final previous = File(out);
    if (previous.existsSync()) previous.deleteSync();

    final result = await channel.invokeMapMethod<String, dynamic>('render', {
      'imagePaths': paths,
      'audioPath': null,
      'perImageMs': 1000,
      'width': 1080,
      'height': 1920,
      'outputPath': out,
    });

    final file = File(result!['filePath'] as String);
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(10000));
    // The ceiling is the assertion that discriminates, not the floor. Three
    // near-static frames encode to roughly 75 KB; frames of garbage YUV are
    // noise and saturate the bitrate cap (1080 * 1920 * 4 bps over 3 s, about
    // 3 MB). Anything approaching that means the conversion is broken.
    expect(file.lengthSync(), lessThan(750000));
    expect(result['audioSkipped'], isTrue);

    // A non-empty file is not enough: an MP4 with a broken moov box passes a
    // size check and fails a user. Decode the container back instead.
    final probe = await channel.invokeMapMethod<String, dynamic>('probe', {
      'path': file.path,
    });
    expect(probe, isNotNull);
    expect(probe!['width'], 1080);
    expect(probe['height'], 1920);
    expect(probe['hasVideo'], isTrue);
    expect(probe['hasAudio'], isFalse);
    // Three images at one second each, allowing for the encoder rounding the
    // last frame's presentation time.
    expect(probe['durationMs'] as int, greaterThan(2500));
    expect(probe['durationMs'] as int, lessThan(3600));

    // Decoding the container proves the file is well formed; it says nothing
    // about the picture. A red/blue swap, a U/V mix-up, a row-stride error or
    // an all-black frame each still yield a valid 1080x1920 / 3 s / video-only
    // MP4. The ARGB-to-I420 conversion and the plane writes are hand rolled,
    // so read the colours back.
    for (var i = 0; i < sizes.length; i++) {
      // Mid-way through each image's second, clear of any boundary frame.
      final atMs = i * 1000 + 400;
      final frame = await channel.invokeMapMethod<String, dynamic>(
        'frameColorAt',
        {'path': file.path, 'atMs': atMs},
      );
      expect(frame, isNotNull, reason: 'no frame decoded at ${atMs}ms');
      final expected = colors[i] & 0xFFFFFF;
      for (final point in ['center', 'topLeft', 'bottomRight']) {
        // Every fixture is a solid colour, so a correct frame is that colour
        // everywhere: the blurred cover and the fitted image agree. Requiring
        // the corners to match the centre is what catches a stride error,
        // which skews the image rather than discolouring it.
        expectColorNear(
          frame![point] as int,
          expected,
          reason: '$point of the frame at ${atMs}ms',
        );
      }
    }

    await file.delete();
    for (final path in paths) {
      await File(path).delete();
    }
  });

  test(
    'a full-resolution phone photo renders without exhausting memory',
    () async {
      // 4032x3024 is what a modern phone camera produces, and it is the case a
      // per-axis downsample guard misses entirely: the short axis (3024) is
      // already under the frame's long one (1920), so a guard joining the two
      // axes with `&&` never fires and the decode allocates ~46 MB of
      // ARGB_8888. The budget is on total pixels for exactly this reason.
      final dir = await getTemporaryDirectory();
      final big = File('${dir.path}/big.png');
      await big.writeAsBytes(await _solidPng(4032, 3024, 0xFFFFB300));
      final out = '${dir.path}/big.mp4';

      final result = await channel.invokeMapMethod<String, dynamic>('render', {
        'imagePaths': [big.path],
        'audioPath': null,
        'perImageMs': 500,
        'width': 1080,
        'height': 1920,
        'outputPath': out,
      });

      final file = File(result!['filePath'] as String);
      expect(file.existsSync(), isTrue);
      // Landscape into portrait: the fitted image letterboxes, so the centre is
      // the photo itself and the corners are the blurred cover behind it. Both
      // come from the same solid source, so both must read as that colour --
      // which also proves the downsampled decode still produced the picture and
      // not a blank or truncated bitmap.
      final frame = await channel.invokeMapMethod<String, dynamic>(
        'frameColorAt',
        {'path': file.path, 'atMs': 200},
      );
      expectColorNear(
        frame!['center'] as int,
        0xFFB300,
        reason: 'centre of the downsampled photo',
      );
      expectColorNear(
        frame['topLeft'] as int,
        0xFFB300,
        reason: 'blurred cover behind the downsampled photo',
      );

      await file.delete();
      await big.delete();
    },
  );

  test('an unreadable image fails with encode_failed', () async {
    final dir = await getTemporaryDirectory();
    final bogus = File('${dir.path}/not_an_image.png');
    await bogus.writeAsString('this is not a png');
    final out = '${dir.path}/broken.mp4';

    await expectLater(
      channel.invokeMapMethod<String, dynamic>('render', {
        'imagePaths': [bogus.path],
        'audioPath': null,
        'perImageMs': 500,
        'width': 720,
        'height': 1280,
        'outputPath': out,
      }),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'encode_failed',
        ),
      ),
    );

    await bogus.delete();
  });
}

/// Asserts an RGB value survived the round trip through BT.601 and 4:2:0
/// chroma subsampling.
///
/// The tolerance covers the conversion's own rounding — measured deltas are
/// two to four per channel — while staying far below the tens-to-hundreds a
/// channel swap or a chroma mix-up produces.
void expectColorNear(int actual, int expected, {required String reason}) {
  const tolerance = 12;
  String hex(int value) => '#${value.toRadixString(16).padLeft(6, '0')}';
  for (final shift in [16, 8, 0]) {
    final channel = ['red', 'green', 'blue'][[16, 8, 0].indexOf(shift)];
    expect(
      (actual >> shift) & 0xFF,
      closeTo((expected >> shift) & 0xFF, tolerance),
      reason:
          '$channel of $reason: got ${hex(actual)}, expected ${hex(expected)}',
    );
  }
}

/// Builds a solid-colour PNG through `dart:ui` so the test needs no image
/// package and no hand-rolled encoder.
Future<Uint8List> _solidPng(int width, int height, int color) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = ui.Color(color),
  );
  final image = await recorder.endRecording().toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
