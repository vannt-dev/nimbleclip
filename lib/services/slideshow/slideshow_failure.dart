enum SlideshowFailureKind {
  noImages,
  fetchFailed,
  encoderUnavailable,
  encodeFailed,
  outOfSpace,

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
