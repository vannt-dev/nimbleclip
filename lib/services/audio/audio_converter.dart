// `dart.library.io` is the only usable discriminator, as for the slideshow
// renderer: it also covers iOS and desktop, which the runtime
// `Platform.isAndroid` gate in the native file turns away.
import 'audio_converter_stub.dart'
    if (dart.library.io) 'audio_converter_android.dart'
    as impl;

enum AudioConversionFailureKind {
  /// This platform has no MP3 encoder.
  unavailable,

  /// [AudioConverter.cancel] was called for the job.
  cancelled,
  outOfSpace,

  /// The source could not be decoded or the encoder gave up.
  failed,
}

class AudioConversionException implements Exception {
  const AudioConversionException(this.kind, {this.detail});

  final AudioConversionFailureKind kind;

  /// What the platform said, for the log; never shown to the user.
  final String? detail;

  @override
  String toString() =>
      'AudioConversionException(${kind.name}${detail == null ? '' : ': $detail'})';
}

/// Re-encodes the sound of a downloaded file as an MP3.
///
/// Implementations are platform-specific and selected via conditional import;
/// see [createAudioConverter].
abstract interface class AudioConverter {
  /// Whether this platform can convert at all.
  bool get isSupported;

  /// Writes the audio of [sourcePath] to [outputPath] as an MP3 and returns
  /// the path written. The source file is left alone.
  ///
  /// [jobId] names the job so [cancel] can address it; [onProgress] is called
  /// with a fraction from 0 to 1. Throws an [AudioConversionException] on
  /// failure, after removing whatever part of the output it wrote.
  Future<String> toMp3({
    required String sourcePath,
    required String outputPath,
    required String jobId,
    void Function(double progress)? onProgress,
  });

  /// Asks the conversion started under [jobId] to stop. Its [toMp3] future
  /// then fails with [AudioConversionFailureKind.cancelled]. A job that is not
  /// running is not an error.
  Future<void> cancel(String jobId);
}

/// Creates the converter for the current platform.
AudioConverter createAudioConverter() => impl.createAudioConverter();
