import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nimble_clip/services/audio/audio_converter.dart';
import 'package:path_provider/path_provider.dart';

/// On-device checks for the MP3 conversion: the platform decoder feeding the
/// bundled LAME encoder.
///
///   flutter test integration_test/mp3_conversion_test.dart -d emulator-5554
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const slideshow = MethodChannel('com.vannt.nimbleclip/slideshow');
  final converter = createAudioConverter();

  Future<Map<String, dynamic>> probe(String path) async => (await slideshow
      .invokeMapMethod<String, dynamic>('probe', {'path': path}))!;

  /// A file that starts with an MPEG-1 Layer III frame header, not with a tag
  /// or with zeroes: `FF FB` is sync, MPEG-1, Layer III, no CRC.
  void expectMp3(File file) {
    final head = file.openSync().readSync(2);
    expect(head[0], 0xFF);
    expect(head[1] & 0xFE, 0xFA);
  }

  test('a stereo recording becomes an MP3 of the same length', () async {
    final dir = await getTemporaryDirectory();
    final source = File('${dir.path}/tone.wav')
      ..writeAsBytesSync(_toneWav(seconds: 3, sampleRate: 44100, channels: 2));
    final out = File('${dir.path}/tone.mp3');
    if (out.existsSync()) out.deleteSync();
    final progress = <double>[];

    final path = await converter.toMp3(
      sourcePath: source.path,
      outputPath: out.path,
      jobId: 'tone',
      onProgress: progress.add,
    );

    expect(path, out.path);
    expectMp3(out);
    // Uncompressed PCM is far above every band, so it takes the top bitrate:
    // 256 kbps for 3 s is 96 kB. Garbage in or a wrong sample rate shows up
    // as a length that is off, which the probe below reads back.
    expect(out.lengthSync(), inInclusiveRange(90000, 102000));
    final info = await probe(out.path);
    expect(info['hasAudio'], isTrue);
    expect(info['durationMs'] as int, inInclusiveRange(2900, 3200));
    expect(progress, isNotEmpty);
    expect(progress.last, 1.0);
    // The source is the user's download until the caller swaps it.
    expect(source.existsSync(), isTrue);
  });

  test('a mono recording at a low rate converts too', () async {
    final dir = await getTemporaryDirectory();
    final source = File('${dir.path}/mono.wav')
      ..writeAsBytesSync(_toneWav(seconds: 2, sampleRate: 22050, channels: 1));
    final out = File('${dir.path}/mono.mp3');
    if (out.existsSync()) out.deleteSync();

    await converter.toMp3(
      sourcePath: source.path,
      outputPath: out.path,
      jobId: 'mono',
    );

    final info = await probe(out.path);
    expect(info['hasAudio'], isTrue);
    expect(info['durationMs'] as int, inInclusiveRange(1900, 2200));
  });

  test('the AAC sound of an MP4 becomes an MP3', () async {
    final dir = await getTemporaryDirectory();
    // An MP4 with an AAC track, made by the slideshow encoder from one image
    // and the tone: the same kind of file an audio download arrives as.
    final image = File('${dir.path}/frame.png')
      ..writeAsBytesSync(await _solidPng());
    final tone = File('${dir.path}/aac_source.wav')
      ..writeAsBytesSync(_toneWav(seconds: 4, sampleRate: 44100, channels: 2));
    final rendered = await slideshow.invokeMapMethod<String, dynamic>(
      'render',
      {
        'imagePaths': [image.path],
        'audioPath': tone.path,
        'perImageMs': 3000,
        'width': 360,
        'height': 640,
        'outputPath': '${dir.path}/aac_source.mp4',
      },
    );
    expect(rendered!['audioSkipped'], isFalse);
    final out = File('${dir.path}/from_aac.mp3');
    if (out.existsSync()) out.deleteSync();

    await converter.toMp3(
      sourcePath: rendered['filePath'] as String,
      outputPath: out.path,
      jobId: 'aac',
    );

    expectMp3(out);
    final info = await probe(out.path);
    expect(info['hasAudio'], isTrue);
    expect(info['hasVideo'], isFalse);
    expect(info['durationMs'] as int, inInclusiveRange(2800, 3600));
  });

  test('a file with no sound fails and leaves nothing behind', () async {
    final dir = await getTemporaryDirectory();
    final source = File('${dir.path}/not_audio.m4a')
      ..writeAsBytesSync(List.filled(4096, 7));
    final out = File('${dir.path}/not_audio.mp3');

    await expectLater(
      converter.toMp3(
        sourcePath: source.path,
        outputPath: out.path,
        jobId: 'bad',
      ),
      throwsA(
        isA<AudioConversionException>().having(
          (error) => error.kind,
          'kind',
          AudioConversionFailureKind.failed,
        ),
      ),
    );
    expect(out.existsSync(), isFalse);
  });

  test('a cancel stops a running conversion and removes its output', () async {
    final dir = await getTemporaryDirectory();
    final source = File(
      '${dir.path}/long.wav',
    )..writeAsBytesSync(_toneWav(seconds: 240, sampleRate: 44100, channels: 2));
    final out = File('${dir.path}/long.mp3');

    final running = converter.toMp3(
      sourcePath: source.path,
      outputPath: out.path,
      jobId: 'long',
      onProgress: (fraction) {
        if (fraction > 0.02) unawaited(converter.cancel('long'));
      },
    );

    await expectLater(
      running,
      throwsA(
        isA<AudioConversionException>().having(
          (error) => error.kind,
          'kind',
          AudioConversionFailureKind.cancelled,
        ),
      ),
    );
    expect(out.existsSync(), isFalse);
    source.deleteSync();
  });
}

/// A 440 Hz tone as a 16-bit PCM WAV file.
Uint8List _toneWav({
  required int seconds,
  required int sampleRate,
  required int channels,
}) {
  final frames = seconds * sampleRate;
  final dataBytes = frames * channels * 2;
  final bytes = ByteData(44 + dataBytes);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, channels, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * channels * 2, Endian.little);
  bytes.setUint16(32, channels * 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, dataBytes, Endian.little);
  for (var frame = 0; frame < frames; frame++) {
    final sample = (math.sin(2 * math.pi * 440 * frame / sampleRate) * 12000)
        .round();
    for (var channel = 0; channel < channels; channel++) {
      bytes.setInt16(
        44 + (frame * channels + channel) * 2,
        sample,
        Endian.little,
      );
    }
  }
  return bytes.buffer.asUint8List();
}

/// The smallest PNG the slideshow encoder accepts: one grey pixel.
Future<Uint8List> _solidPng() async {
  const base64Png =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNoaGj4DwAFhAKAjM1mJgAAAABJRU5ErkJggg==';
  return base64Decode(base64Png);
}
