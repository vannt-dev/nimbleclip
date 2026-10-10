import '../models/merge_source.dart';

/// The two whole files of a merged video, ready to be joined.
typedef StreamPairFiles = ({String videoPath, String audioPath});

/// Fetches both streams of a merged video as operating-system transfers, so
/// the fetch carries on when Android ends the app's process.
///
/// Only the fetch is handed over: joining the streams needs the app, so a
/// transfer that finishes while the app is gone waits for the next launch.
abstract interface class StreamPairGateway {
  /// Queues every part of [source]'s two streams for [taskId].
  ///
  /// Throws a `SlideshowException` when the streams cannot be queued, for
  /// example when their sizes cannot be confirmed.
  Future<StreamPairTransfer> startStreamPair({
    required String taskId,
    required String title,
    required MergeSource source,
    required bool autoSaveToGallery,
  });

  /// Transfers an earlier process left behind, found while recovering
  /// downloads. Each is handed out once.
  List<StreamPairTransfer> takeRecoveredStreamPairs();

  /// Stops [taskId]'s transfer; its [StreamPairTransfer.files] then fails with
  /// a cancelled `SlideshowException`.
  void cancelStreamPair(String taskId);
}

/// One file fetched in parts as operating-system transfers and joined where it
/// is wanted.
abstract interface class SingleStreamTransfer {
  String get taskId;
  int get totalBytes;

  /// Where the whole file is written.
  String get outputPath;

  /// Completes with [outputPath] once every part has arrived and the file is
  /// whole. Fails with a `SlideshowException`.
  Future<String> get file;

  /// Called with the running total and the combined transfer speed.
  set onProgress(void Function(int receivedBytes, double bytesPerSecond)? cb);

  /// Deletes the parts and the transfer's own records. The finished file, if
  /// there is one, stays.
  Future<void> discard();
}

abstract interface class StreamPairTransfer {
  String get taskId;
  bool get autoSaveToGallery;

  /// Both streams together, in bytes.
  int get totalBytes;

  /// Completes once every part has arrived and each stream is one file.
  /// Fails with a `SlideshowException`.
  Future<StreamPairFiles> get files;

  /// Called with the running total and the combined transfer speed.
  set onProgress(void Function(int receivedBytes, double bytesPerSecond)? cb);

  /// Deletes every part and file the transfer wrote.
  Future<void> discard();
}
