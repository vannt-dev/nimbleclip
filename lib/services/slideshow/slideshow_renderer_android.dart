import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'slideshow_renderer.dart';

/// Renders a slideshow through the Android `MediaCodec` encoder behind
/// `com.vannt.nimbleclip/slideshow`.
class MethodChannelSlideshowRenderer implements SlideshowRenderer {
  const MethodChannelSlideshowRenderer();

  static const MethodChannel _channel = MethodChannel(
    'com.vannt.nimbleclip/slideshow',
  );

  /// Only Android has the encoder.
  ///
  /// The runtime check is load-bearing, not belt-and-braces. A conditional
  /// import selects on which `dart:*` library exists, and `dart.library.io` is
  /// true on iOS as well — there is no `dart.library.android` — so pointing the
  /// native branch at this file makes iOS import it too. Without this gate iOS
  /// would report a renderer it does not have, show the option, and fail at the
  /// channel call.
  @override
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  @override
  Future<SlideshowResult> render({
    required List<String> imagePaths,
    String? audioPath,
    required Duration perImage,
    required int width,
    required int height,
    required String outputPath,
  }) async {
    if (!isSupported) {
      throw const SlideshowException(SlideshowFailureKind.encoderUnavailable);
    }
    if (imagePaths.isEmpty) {
      throw const SlideshowException(SlideshowFailureKind.noImages);
    }

    final Map<String, dynamic>? result;
    try {
      result = await _channel.invokeMapMethod<String, dynamic>('render', {
        'imagePaths': imagePaths,
        'audioPath': audioPath,
        // The interface keeps a Duration because that is the idiomatic Dart
        // type; the channel boundary is where units get flattened.
        'perImageMs': perImage.inMilliseconds,
        'width': width,
        'height': height,
        'outputPath': outputPath,
      });
    } on PlatformException catch (error) {
      throw SlideshowException(_kindFor(error.code), detail: error.message);
    } on MissingPluginException catch (error) {
      // An Android build that predates the channel: the option is offered but
      // nothing answers it.
      throw SlideshowException(
        SlideshowFailureKind.encoderUnavailable,
        detail: error.message,
      );
    }

    final filePath = result?['filePath'] as String?;
    if (filePath == null || filePath.isEmpty) {
      throw const SlideshowException(
        SlideshowFailureKind.encodeFailed,
        detail: 'the encoder returned no file path',
      );
    }
    return SlideshowResult(
      filePath: filePath,
      audioSkipped: result?['audioSkipped'] as bool? ?? true,
    );
  }

  /// The channel raises exactly two codes today. Everything else — including a
  /// code a future build adds — is an encode failure, which is what the caller
  /// would do with an unknown one anyway.
  SlideshowFailureKind _kindFor(String code) => switch (code) {
    'out_of_space' => SlideshowFailureKind.outOfSpace,
    _ => SlideshowFailureKind.encodeFailed,
  };
}

SlideshowRenderer createSlideshowRenderer() =>
    const MethodChannelSlideshowRenderer();
