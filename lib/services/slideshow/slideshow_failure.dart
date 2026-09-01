enum SlideshowFailureKind {
  noImages,
  fetchFailed,
  encoderUnavailable,
  encodeFailed,
  outOfSpace,
}

class SlideshowException implements Exception {
  const SlideshowException(this.kind, {this.detail});

  final SlideshowFailureKind kind;
  final String? detail;

  @override
  String toString() =>
      'SlideshowException($kind${detail != null ? ': $detail' : ''})';
}
