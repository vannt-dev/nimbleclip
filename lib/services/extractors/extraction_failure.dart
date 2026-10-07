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

  /// Facebook gates the post as 18+, which no anonymous request can pass.
  /// Distinct from [facebookNoVideo] because the post may well be public, and
  /// telling the user to check that it is wastes their time.
  facebookAgeRestricted,

  genericNoVideo,

  /// The page declares its video only as an HLS or DASH playlist, which has
  /// no single file behind it.
  genericStreamOnly,

  /// The stream is still being broadcast, so it has no end to download to.
  genericStreamLive,

  /// The stream's segments are encrypted.
  genericStreamProtected,
  instagramInvalidPost,
  instagramLoginRequired,

  /// Detail: the underlying error.
  tiktokConnectionFailed,

  /// Detail: the message TikTok supplied, when it supplied one.
  tiktokInvalidData,

  tiktokNoStreams,

  /// Detail: the HTTP status TikTok returned.
  tiktokServiceStatus,

  threadsInvalidPost,

  /// The post is text only, private, deleted, or Threads did not include its
  /// media in the page.
  threadsNoMedia,

  xInvalidPost,
  xNoVideo,
  youtubeCipherUnsupported,
  youtubeInvalidId,
  youtubeNoPlayerData,
  youtubeNoStreams,

  /// A playlist page listed no videos: it is private, removed or empty.
  youtubePlaylistUnavailable,

  /// Detail: the underlying error.
  youtubeInvalidData,

  /// Detail: the underlying error.
  youtubeLoadFailed,

  /// Detail: the reason YouTube gave.
  youtubePlaybackRejected,

  /// YouTube kept refusing the page after the library's own retries: it is
  /// throttling this client, and the video itself may be fine.
  youtubeTemporarilyUnavailable,
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
