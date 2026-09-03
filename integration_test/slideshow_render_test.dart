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

  test('a slideshow with music carries an audio track', () async {
    final dir = await getTemporaryDirectory();
    final paths = await writeFixtures(dir);
    final song = File('${dir.path}/song.mp3');
    // Four seconds against three of pictures, so the trim to the video's
    // length is exercised rather than the song simply running out first.
    await song.writeAsBytes(_silentMp3(seconds: 4));
    final out = '${dir.path}/with_music.mp4';

    final result = await channel.invokeMapMethod<String, dynamic>('render', {
      'imagePaths': paths,
      'audioPath': song.path,
      'perImageMs': 1000,
      'width': 1080,
      'height': 1920,
      'outputPath': out,
    });

    expect(result!['audioSkipped'], isFalse);
    final file = File(result['filePath'] as String);
    expect(file.existsSync(), isTrue);

    final probe = await channel.invokeMapMethod<String, dynamic>('probe', {
      'path': file.path,
    });
    expect(probe!['hasAudio'], isTrue);
    // The picture has to survive the second track: a muxer started before both
    // tracks were added, or an audio packet written against the video track,
    // both yield a file that still opens.
    expect(probe['hasVideo'], isTrue);
    expect(probe['width'], 1080);
    expect(probe['height'], 1920);
    // The music is a second longer than the slideshow. If the trim were
    // missing the container would report four seconds, not three.
    expect(probe['durationMs'] as int, greaterThan(2500));
    expect(probe['durationMs'] as int, lessThan(3600));

    final frame = await channel.invokeMapMethod<String, dynamic>(
      'frameColorAt',
      {'path': file.path, 'atMs': 1400},
    );
    expectColorNear(
      frame!['center'] as int,
      colors[1] & 0xFFFFFF,
      reason: 'centre of the second image once music is muxed alongside it',
    );

    await file.delete();
    await song.delete();
    for (final path in paths) {
      await File(path).delete();
    }
  });

  test('a corrupt track yields a silent video, not a failure', () async {
    final dir = await getTemporaryDirectory();
    final paths = await writeFixtures(dir);
    final song = File('${dir.path}/corrupt.mp3');
    // Bytes that genuinely fail to decode, not merely a wrong extension: a
    // missing file and a malformed one take different paths through the
    // transcode, and the fallback has to hold for both.
    await song.writeAsBytes(_corruptAudioBytes());
    final out = '${dir.path}/corrupt_music.mp4';

    final result = await channel.invokeMapMethod<String, dynamic>('render', {
      'imagePaths': paths,
      'audioPath': song.path,
      'perImageMs': 1000,
      'width': 1080,
      'height': 1920,
      'outputPath': out,
    });

    // The render must not fail. A slideshow without music is usable; an
    // exception here would lose the whole thing over the soundtrack.
    expect(result!['audioSkipped'], isTrue);
    final file = File(result['filePath'] as String);
    expect(file.existsSync(), isTrue);

    final probe = await channel.invokeMapMethod<String, dynamic>('probe', {
      'path': file.path,
    });
    expect(probe!['hasAudio'], isFalse);
    expect(probe['hasVideo'], isTrue);
    expect(probe['durationMs'] as int, greaterThan(2500));

    // A half-written audio stage must leave the picture untouched, which is
    // the whole reason the transcode runs before the muxer is started.
    final frame = await channel.invokeMapMethod<String, dynamic>(
      'frameColorAt',
      {'path': file.path, 'atMs': 2400},
    );
    expectColorNear(
      frame!['center'] as int,
      colors[2] & 0xFFFFFF,
      reason: 'centre of the third image after the audio stage gave up',
    );

    await file.delete();
    await song.delete();
    for (final path in paths) {
      await File(path).delete();
    }
  });

  test('a missing audio file yields a silent video, not a failure', () async {
    final dir = await getTemporaryDirectory();
    final paths = await writeFixtures(dir);
    final missing = '${dir.path}/no_such_song.mp3';
    final absent = File(missing);
    if (absent.existsSync()) absent.deleteSync();
    final out = '${dir.path}/missing_music.mp4';

    final result = await channel.invokeMapMethod<String, dynamic>('render', {
      'imagePaths': paths,
      'audioPath': missing,
      'perImageMs': 1000,
      'width': 1080,
      'height': 1920,
      'outputPath': out,
    });

    expect(result!['audioSkipped'], isTrue);
    final file = File(result['filePath'] as String);
    expect(file.existsSync(), isTrue);

    final probe = await channel.invokeMapMethod<String, dynamic>('probe', {
      'path': file.path,
    });
    expect(probe!['hasAudio'], isFalse);
    expect(probe['hasVideo'], isTrue);
    expect(probe['durationMs'] as int, greaterThan(2500));

    await file.delete();
    for (final path in paths) {
      await File(path).delete();
    }
  });
}

/// Builds a real MPEG-1 Layer III file: 44.1 kHz, stereo, 128 kbps — the shape
/// TikWM serves.
///
/// Synthesised rather than committed as a binary because the alternative
/// needs an MP3 encoder on the machine running the tests, and neither ffmpeg
/// nor lame is a dependency of this repo.
///
/// The audio is silence, which the format expresses exactly: with the whole
/// side-info block zeroed, `part2_3_length` is zero for both granules, so each
/// frame carries no scalefactors and no Huffman data and the decoder emits
/// zero samples. The bytes are still a genuine MP3 — the platform's own MP3
/// decoder parses the headers, produces PCM and drives the AAC encoder, which
/// is the path under test. What the samples contain is not: no assertion here
/// reads the waveform back.
Uint8List _silentMp3({required int seconds}) {
  // MPEG-1 Layer III, no CRC, 128 kbps, 44100 Hz, stereo.
  const header = <int>[0xFF, 0xFB, 0x90, 0x00];
  // floor(144 * bitrate / sampleRate), with no padding byte.
  const frameBytes = 417;
  // One Layer III frame is 1152 samples.
  final frames = (seconds * 44100 / 1152).ceil();
  final bytes = Uint8List(frames * frameBytes);
  for (var frame = 0; frame < frames; frame++) {
    bytes.setRange(frame * frameBytes, frame * frameBytes + 4, header);
    // Side info and main data stay zero.
  }
  return bytes;
}

/// Bytes that no audio decoder can make sense of.
///
/// Deliberately not random: a run that fails has to be reproducible. Also
/// deliberately free of an 0xFF 0xE0 sync pattern, so the failure is the
/// extractor finding no audio track at all rather than a decoder that limps
/// along on one accidental frame.
Uint8List _corruptAudioBytes() {
  final bytes = Uint8List(8192);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = (i * 37 + 11) % 251;
  }
  return bytes;
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
