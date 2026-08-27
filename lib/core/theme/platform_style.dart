import 'package:flutter/material.dart';

import '../../models/video_platform.dart';
import '../constants/app_colors.dart';

/// Brand colour and icon for a platform.
///
/// These live in the theme layer rather than on the enum: a domain type should
/// not have to import Flutter's material library to describe itself. Written as
/// an extension so every call site keeps reading `platform.brandColor`
/// unchanged.
extension PlatformStyle on VideoPlatform {
  Color get brandColor => switch (this) {
    VideoPlatform.youtube => AppColors.youtube,
    VideoPlatform.tiktok => AppColors.tiktok,
    VideoPlatform.facebook => AppColors.facebook,
    VideoPlatform.twitter => AppColors.twitter,
    VideoPlatform.instagram => AppColors.instagram,
    VideoPlatform.generic => AppColors.primary,
  };

  IconData get icon => switch (this) {
    VideoPlatform.youtube => Icons.play_circle_fill_rounded,
    VideoPlatform.tiktok => Icons.music_note_rounded,
    VideoPlatform.facebook => Icons.facebook_rounded,
    VideoPlatform.twitter => Icons.flutter_dash_rounded,
    VideoPlatform.instagram => Icons.camera_alt_rounded,
    VideoPlatform.generic => Icons.link_rounded,
  };
}
