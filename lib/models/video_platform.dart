enum VideoPlatform {
  youtube,
  tiktok,
  facebook,
  twitter,
  instagram,
  threads,
  generic;

  String get displayName {
    switch (this) {
      case VideoPlatform.youtube:
        return 'YouTube';
      case VideoPlatform.tiktok:
        return 'TikTok';
      case VideoPlatform.facebook:
        return 'Facebook';
      case VideoPlatform.twitter:
        return 'Twitter / X';
      case VideoPlatform.instagram:
        return 'Instagram';
      case VideoPlatform.threads:
        return 'Threads';
      case VideoPlatform.generic:
        return 'Direct Link';
    }
  }
}
