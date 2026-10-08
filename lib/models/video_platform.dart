enum VideoPlatform {
  youtube,
  tiktok,
  facebook,
  twitter,
  instagram,
  threads,
  pinterest,
  soundcloud,
  flickr,
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
      case VideoPlatform.pinterest:
        return 'Pinterest';
      case VideoPlatform.soundcloud:
        return 'SoundCloud';
      case VideoPlatform.flickr:
        return 'Flickr';
      case VideoPlatform.generic:
        return 'Direct Link';
    }
  }
}
