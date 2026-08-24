/// Runtime privacy policy shared by extractors.
///
/// Public social pages frequently omit the original media URLs. In that case
/// NimbleClip can send the public post URL/id to an external extraction
/// service. The setting is enabled by default to preserve download support,
/// but users can disable it at any time.
class ExternalServicePolicy {
  ExternalServicePolicy._();

  static bool allowExternalServices = true;
}
