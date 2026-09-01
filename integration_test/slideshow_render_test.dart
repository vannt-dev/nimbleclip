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

    await file.delete();
    for (final path in paths) {
      await File(path).delete();
    }
  });

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
