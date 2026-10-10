import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../models/video_platform.dart';
import '../constants/app_colors.dart';

/// Brand colour and icon for a platform. The icons are the platforms' own
/// marks, from Font Awesome's brand set, so a row of them is recognised
/// without their names.
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
    VideoPlatform.threads => AppColors.threads,
    VideoPlatform.pinterest => AppColors.pinterest,
    VideoPlatform.soundcloud => AppColors.soundcloud,
    VideoPlatform.flickr => AppColors.flickr,
    VideoPlatform.generic => AppColors.primary,
  };

  /// The platform's own mark; null for a link that belongs to no platform.
  FaIconData? get brandMark => switch (this) {
    VideoPlatform.youtube => FontAwesomeIcons.youtube,
    VideoPlatform.tiktok => FontAwesomeIcons.tiktok,
    VideoPlatform.facebook => FontAwesomeIcons.facebook,
    VideoPlatform.twitter => FontAwesomeIcons.xTwitter,
    VideoPlatform.instagram => FontAwesomeIcons.instagram,
    VideoPlatform.threads => FontAwesomeIcons.threads,
    VideoPlatform.pinterest => FontAwesomeIcons.pinterest,
    VideoPlatform.soundcloud => FontAwesomeIcons.soundcloud,
    VideoPlatform.flickr => FontAwesomeIcons.flickr,
    VideoPlatform.generic => null,
  };
}

/// A platform's icon. A mark is drawn at its own width, since some (YouTube,
/// SoundCloud) are wider than they are tall and would spill out of the square
/// a plain [Icon] gives them, into the text beside it.
class PlatformIcon extends StatelessWidget {
  const PlatformIcon(
    this.platform, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  final VideoPlatform platform;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final mark = platform.brandMark;
    if (mark == null) {
      return Icon(
        Icons.link_rounded,
        size: size,
        color: color,
        semanticLabel: semanticLabel,
      );
    }
    return FaIcon(mark, size: size, color: color, semanticLabel: semanticLabel);
  }
}
