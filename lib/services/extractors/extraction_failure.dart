/// Why an extraction stopped.
///
/// Extractors report a kind rather than a sentence so that the layer stays
/// free of presentation text: the same failure renders differently per locale,
/// and tests can assert on identity instead of English prose.
enum ExtractionFailureKind {
  invalidLink,
  noDownloadStreams,
  externalServicesDisabled,

  /// Detail: the underlying error.
  linkAccessFailed,

  facebookNoVideo,
  genericNoVideo,
  instagramInvalidPost,
  instagramLoginRequired,

  /// Detail: the underlying error.
  tiktokConnectionFailed,

  /// Detail: the message TikTok supplied, when it supplied one.
  tiktokInvalidData,

  tiktokNoStreams,

  /// Detail: the HTTP status TikTok returned.
  tiktokServiceStatus,

  xInvalidPost,
  xNoVideo,
  youtubeCipherUnsupported,
  youtubeInvalidId,
  youtubeNoPlayerData,
  youtubeNoStreams,

  /// Detail: the underlying error.
  youtubeInvalidData,

  /// Detail: the underlying error.
  youtubeLoadFailed,

  /// Detail: the reason YouTube gave.
  youtubePlaybackRejected,
}

/// A failure kind plus the one piece of context some kinds carry.
///
/// A single nullable [detail] rather than a payload type per kind: six kinds
/// use it, each with exactly one substitution, and each is already a string at
/// the throw site. Kinds that take no detail ignore one if it is supplied.
class ExtractionFailure {
  const ExtractionFailure(this.kind, {this.detail});

  final ExtractionFailureKind kind;
  final String? detail;

  @override
  String toString() => detail == null
      ? 'ExtractionFailure(${kind.name})'
      : 'ExtractionFailure(${kind.name}, $detail)';
}
