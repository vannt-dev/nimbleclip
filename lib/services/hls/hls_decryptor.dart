import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../slideshow/slideshow_failure.dart';

/// Writes the plain bytes of [encrypted] to [into]: AES-128 in CBC mode with
/// PKCS#7 padding, which is what a playlist's `METHOD=AES-128` means.
typedef HlsDecryptor =
    Future<void> Function(
      File encrypted,
      File into,
      List<int> key,
      List<int> initializationVector,
    );

/// The decryptor this platform has, or null where there is none. Streams are
/// joined on Android only, so that is the only place one is needed.
HlsDecryptor? platformHlsDecryptor() =>
    !kIsWeb && Platform.isAndroid ? _decryptOnAndroid : null;

const MethodChannel _channel = MethodChannel('com.vannt.nimbleclip/slideshow');

Future<void> _decryptOnAndroid(
  File encrypted,
  File into,
  List<int> key,
  List<int> initializationVector,
) async {
  try {
    await _channel.invokeMethod<void>('decryptSegment', {
      'sourcePath': encrypted.path,
      'outputPath': into.path,
      'key': Uint8List.fromList(key),
      'iv': Uint8List.fromList(initializationVector),
    });
  } on PlatformException catch (error) {
    // A wrong key shows as bad padding at the end of the segment: the stream
    // is protected by something the playlist did not say.
    throw SlideshowException(
      error.code == 'out_of_space'
          ? SlideshowFailureKind.outOfSpace
          : SlideshowFailureKind.streamProtected,
      detail: error.message,
    );
  } on MissingPluginException catch (error) {
    throw SlideshowException(
      SlideshowFailureKind.streamProtected,
      detail: error.message,
    );
  }
}
