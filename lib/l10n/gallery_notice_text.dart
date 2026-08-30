import '../models/gallery_notice.dart';
import 'generated/app_localizations.dart';

/// Renders [notice] in the caller's language.
///
/// The switch is exhaustive on purpose: adding a notice without adding its
/// text is a compile error rather than a blank line in the UI.
String describeGalleryNotice(GalleryNotice notice, AppLocalizations l10n) {
  return switch (notice) {
    GalleryNotice.externalServicesDisabled => l10n.galleryMayBeIncomplete,
    GalleryNotice.galleryCheckUnavailable => l10n.galleryCheckUnavailable,
  };
}
