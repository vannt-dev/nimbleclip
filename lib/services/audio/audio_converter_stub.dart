import 'audio_converter.dart';

/// Fallback for Web, where nothing can encode an MP3.
class UnsupportedAudioConverter implements AudioConverter {
  const UnsupportedAudioConverter();

  @override
  bool get isSupported => false;

  @override
  Future<String> toMp3({
    required String sourcePath,
    required String outputPath,
    required String jobId,
    void Function(double progress)? onProgress,
  }) async {
    throw const AudioConversionException(
      AudioConversionFailureKind.unavailable,
    );
  }

  /// Nothing can be running, so there is nothing to stop.
  @override
  Future<void> cancel(String jobId) async {}
}

AudioConverter createAudioConverter() => const UnsupportedAudioConverter();
