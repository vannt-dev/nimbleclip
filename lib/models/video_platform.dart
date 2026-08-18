import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';

enum VideoPlatform {
  youtube,
  tiktok,
  facebook,
  twitter,
  instagram,
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
      case VideoPlatform.generic:
        return 'Direct Link';
    }
  }

  Color get brandColor {
    switch (this) {
      case VideoPlatform.youtube:
        return AppColors.youtube;
      case VideoPlatform.tiktok:
        return AppColors.tiktok;
      case VideoPlatform.facebook:
        return AppColors.facebook;
      case VideoPlatform.twitter:
        return AppColors.twitter;
      case VideoPlatform.instagram:
        return AppColors.instagram;
      case VideoPlatform.generic:
        return AppColors.primary;
    }
  }

  IconData get icon {
    switch (this) {
      case VideoPlatform.youtube:
        return Icons.play_circle_fill_rounded;
      case VideoPlatform.tiktok:
        return Icons.music_note_rounded;
      case VideoPlatform.facebook:
        return Icons.facebook_rounded;
      case VideoPlatform.twitter:
        return Icons.flutter_dash_rounded;
      case VideoPlatform.instagram:
        return Icons.camera_alt_rounded;
      case VideoPlatform.generic:
        return Icons.link_rounded;
    }
  }
}
