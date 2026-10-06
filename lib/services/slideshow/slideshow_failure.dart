enum SlideshowFailureKind {
  noImages,
  fetchFailed,
  encoderUnavailable,
  encodeFailed,
  outOfSpace,

  /// A stream that is still being broadcast: its playlist has no end.
  streamLive,

  /// A stream whose segments are encrypted.
  streamProtected,

  /// A stream whose segments were fetched but could not be joined into a
  /// file, for example because the device has no demuxer for its codec.
  streamUnreadable,

  /// The caller asked for the render to stop. Not an error to report: the task
  /// carries the user's own decision, so it must not be dressed up as one.
  cancelled,
}

class SlideshowException implements Exception {
  const SlideshowException(this.kind, {this.detail});

  final SlideshowFailureKind kind;
  final String? detail;

  @override
  String toString() =>
      'SlideshowException($kind${detail != null ? ': $detail' : ''})';
}
