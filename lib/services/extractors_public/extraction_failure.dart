/// Why a link could not be turned into a download.
///
/// The kinds are the ones the app has a sentence for (see
/// `describeExtractionFailure`), so this list is the same in the public core
/// and in the full one; the public core raises only a few of them.
enum ExtractionFailureKind {
  invalidLink,
  noDownloadStreams,
  externalServicesDisabled,
  linkAccessFailed,
  facebookNoVideo,
  facebookAgeRestricted,
  genericNoVideo,
  genericStreamOnly,
  genericStreamLive,
  genericStreamProtected,
  instagramInvalidPost,
  instagramLoginRequired,
  tiktokConnectionFailed,
  tiktokInvalidData,
  tiktokNoStreams,
  tiktokServiceStatus,
  threadsInvalidPost,
  threadsNoMedia,
  soundcloudNotATrack,
  soundcloudUnavailable,
  pinterestNoMedia,
  flickrInvalidLink,
  flickrUnavailable,
  flickrDownloadDisabled,
  xInvalidPost,
  xNoVideo,
  youtubeCipherUnsupported,
  youtubeInvalidId,
  youtubeNoPlayerData,
  youtubeNoStreams,
  youtubePlaylistUnavailable,
  youtubeInvalidData,
  youtubeLoadFailed,
  youtubePlaybackRejected,
  youtubeTemporarilyUnavailable,
}

class ExtractionFailure {
  const ExtractionFailure(this.kind, {this.detail});

  final ExtractionFailureKind kind;
  final String? detail;

  @override
  String toString() => detail == null
      ? 'ExtractionFailure(${kind.name})'
      : 'ExtractionFailure(${kind.name}, $detail)';
}
