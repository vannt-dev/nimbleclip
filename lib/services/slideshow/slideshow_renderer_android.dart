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

  /// Progress listeners by render id.
  ///
  /// Static because the channel is: Kotlin reports progress by calling back on
  /// the same channel, and a handler can only be installed once per channel
  /// per isolate. Keyed by id rather than held as a single field so a stale
  /// event from a finished render cannot drive a later one's bar.
  static final Map<String, void Function(double)> _listeners = {};
  static bool _handlerInstalled = false;

  static void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'progress') return null;
      final arguments = call.arguments;
      if (arguments is! Map) return null;
      final id = arguments['renderId'] as String?;
      final progress = (arguments['progress'] as num?)?.toDouble();
      if (id == null || progress == null) return null;
      _listeners[id]?.call(progress.clamp(0.0, 1.0));
      return null;
    });
  }

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
    String? renderId,
    void Function(double progress)? onProgress,
  }) async {
    if (!isSupported) {
      throw const SlideshowException(SlideshowFailureKind.encoderUnavailable);
    }
    if (imagePaths.isEmpty) {
      throw const SlideshowException(SlideshowFailureKind.noImages);
    }

    // Kotlin needs an id whether or not the caller wanted one, so a cancel can
    // always name a target.
    final id = renderId ?? 'render_${DateTime.now().microsecondsSinceEpoch}';
    if (onProgress != null) {
      _installHandler();
      _listeners[id] = onProgress;
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
        'renderId': id,
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
    } finally {
      // Whatever happened, no later event may reach this caller's callback.
      _listeners.remove(id);
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

  @override
  Future<void> cancel(String renderId) async {
    if (!isSupported) return;
    _listeners.remove(renderId);
    try {
      await _channel.invokeMethod<void>('cancel', {'renderId': renderId});
    } on PlatformException {
      // The render finished on its own between the tap and this call. Its own
      // result is the truth; there is nothing left to stop.
    } on MissingPluginException {
      // Same reasoning as in render: an older build without the channel.
    }
  }

  /// The channel raises three codes today. Everything else — including a code
  /// a future build adds — is an encode failure, which is what the caller
  /// would do with an unknown one anyway.
  SlideshowFailureKind _kindFor(String code) => switch (code) {
    'out_of_space' => SlideshowFailureKind.outOfSpace,
    'cancelled' => SlideshowFailureKind.cancelled,
    _ => SlideshowFailureKind.encodeFailed,
  };
}

SlideshowRenderer createSlideshowRenderer() =>
    const MethodChannelSlideshowRenderer();
