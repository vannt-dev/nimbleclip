import '../services/extractors/extraction_failure.dart';
import 'generated/app_localizations.dart';

/// Renders [failure] in the caller's language.
///
/// The switch is exhaustive on purpose: adding a kind without adding its text
/// is a compile error rather than a blank message in the UI.
String describeExtractionFailure(
  ExtractionFailure failure,
  AppLocalizations l10n,
) {
  final detail = failure.detail;
  return switch (failure.kind) {
    ExtractionFailureKind.invalidLink => l10n.invalidLink,
    ExtractionFailureKind.noDownloadStreams => l10n.noDownloadStreams,
    ExtractionFailureKind.externalServicesDisabled =>
      l10n.externalServicesDisabled,
    ExtractionFailureKind.linkAccessFailed => l10n.linkAccessFailed(
      detail ?? '',
    ),
    ExtractionFailureKind.facebookNoVideo => l10n.facebookNoVideo,
    ExtractionFailureKind.facebookAgeRestricted => l10n.facebookAgeRestricted,
    ExtractionFailureKind.genericNoVideo => l10n.genericNoVideo,
    ExtractionFailureKind.instagramInvalidPost => l10n.instagramInvalidPost,
    ExtractionFailureKind.instagramLoginRequired => l10n.instagramLoginRequired,
    ExtractionFailureKind.tiktokConnectionFailed => l10n.tiktokConnectionFailed(
      detail ?? '',
    ),
    // TikTok sometimes explains the failure itself. That text is not
    // translatable, so it is shown verbatim when present.
    ExtractionFailureKind.tiktokInvalidData =>
      detail != null && detail.isNotEmpty
          ? 'TikTok: $detail'
          : l10n.tiktokInvalidData,
    ExtractionFailureKind.tiktokNoStreams => l10n.tiktokNoStreams,
    ExtractionFailureKind.tiktokServiceStatus => l10n.tiktokServiceStatus(
      int.tryParse(detail ?? '') ?? 0,
    ),
    ExtractionFailureKind.xInvalidPost => l10n.xInvalidPost,
    ExtractionFailureKind.xNoVideo => l10n.xNoVideo,
    ExtractionFailureKind.youtubeCipherUnsupported =>
      l10n.youtubeCipherUnsupported,
    ExtractionFailureKind.youtubeInvalidId => l10n.youtubeInvalidId,
    ExtractionFailureKind.youtubeNoPlayerData => l10n.youtubeNoPlayerData,
    ExtractionFailureKind.youtubeNoStreams => l10n.youtubeNoStreams,
    ExtractionFailureKind.youtubeInvalidData => l10n.youtubeInvalidData(
      detail ?? '',
    ),
    ExtractionFailureKind.youtubeLoadFailed => l10n.youtubeLoadFailed(
      detail ?? '',
    ),
    ExtractionFailureKind.youtubePlaybackRejected =>
      l10n.youtubePlaybackRejected(detail ?? ''),
  };
}
