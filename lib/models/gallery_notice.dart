/// Why a result may be holding fewer photos than the post does.
///
/// A gallery reaches the app only through the external fallback service:
/// Facebook serves an anonymous request no photo set of its own, just the
/// Open Graph cover. When that service is unavailable the result is a single
/// photo, which is indistinguishable from a post that genuinely holds one.
/// A notice says which of the two happened, so the app reports a gap instead
/// of quietly presenting a cover photo as the whole post.
///
/// Absent whenever the count is trustworthy: the service answered, and what it
/// answered with is what the result carries.
enum GalleryNotice {
  /// The user turned external services off, so the set was never requested.
  /// The one case the reader can act on themselves.
  externalServicesDisabled,

  /// The service was asked and did not answer — a transport failure, a refused
  /// status, or a payload that did not parse. Whether more photos exist is
  /// unknown, which is precisely what is worth saying.
  galleryCheckUnavailable,
}
