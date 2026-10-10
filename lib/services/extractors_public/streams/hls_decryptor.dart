import 'dart:io';

/// Writes the plain bytes of [encrypted] to [into].
typedef HlsDecryptor =
    Future<void> Function(
      File encrypted,
      File into,
      List<int> key,
      List<int> initializationVector,
    );

/// The decryptor this platform has. The public core follows no stream, so it
/// has none.
HlsDecryptor? platformHlsDecryptor() => null;
