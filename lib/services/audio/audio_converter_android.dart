import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio_converter.dart';

/// Converts through the Android decoder and the bundled LAME encoder behind
/// `com.vannt.nimbleclip/audio`.
class MethodChannelAudioConverter implements AudioConverter {
  const MethodChannelAudioConverter();

  static const MethodChannel _channel = MethodChannel(
    'com.vannt.nimbleclip/audio',
  );

  /// Progress listeners by job id; static because the channel's one handler
  /// is, and keyed so a late event from a finished job reaches nobody.
  static final Map<String, void Function(double)> _listeners = {};
  static bool _handlerInstalled = false;

  static void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'progress') return null;
      final arguments = call.arguments;
      if (arguments is! Map) return null;
      final id = arguments['jobId'] as String?;
      final progress = (arguments['progress'] as num?)?.toDouble();
      if (id == null || progress == null) return null;
      _listeners[id]?.call(progress.clamp(0.0, 1.0));
      return null;
    });
  }

  /// Only Android carries the encoder; this file is also what iOS and desktop
  /// import, so the runtime check is what keeps the option away from them.
  @override
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  @override
  Future<String> toMp3({
    required String sourcePath,
    required String outputPath,
    required String jobId,
    void Function(double progress)? onProgress,
  }) async {
    if (!isSupported) {
      throw const AudioConversionException(
        AudioConversionFailureKind.unavailable,
      );
    }
    if (onProgress != null) {
      _installHandler();
      _listeners[jobId] = onProgress;
    }

    final Map<String, dynamic>? result;
    try {
      result = await _channel.invokeMapMethod<String, dynamic>('toMp3', {
        'sourcePath': sourcePath,
        'outputPath': outputPath,
        'jobId': jobId,
      });
    } on PlatformException catch (error) {
      throw AudioConversionException(switch (error.code) {
        'cancelled' => AudioConversionFailureKind.cancelled,
        'out_of_space' => AudioConversionFailureKind.outOfSpace,
        _ => AudioConversionFailureKind.failed,
      }, detail: error.message);
    } on MissingPluginException catch (error) {
      throw AudioConversionException(
        AudioConversionFailureKind.unavailable,
        detail: error.message,
      );
    } finally {
      _listeners.remove(jobId);
    }

    final filePath = result?['filePath'] as String?;
    if (filePath == null || filePath.isEmpty) {
      throw const AudioConversionException(
        AudioConversionFailureKind.failed,
        detail: 'the converter returned no file path',
      );
    }
    return filePath;
  }

  @override
  Future<void> cancel(String jobId) async {
    if (!isSupported) return;
    _listeners.remove(jobId);
    try {
      await _channel.invokeMethod<void>('cancel', {'jobId': jobId});
    } on PlatformException {
      // The job ended on its own between the tap and this call.
    } on MissingPluginException {
      // An older build without the channel has nothing to stop.
    }
  }
}

AudioConverter createAudioConverter() => const MethodChannelAudioConverter();
