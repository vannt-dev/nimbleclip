import 'dart:io';

import 'package:video_player/video_player.dart';

/// Builds a player for a file already on disk.
///
/// A local path is not a URL: `VideoPlayerController.networkUrl` on
/// `/data/user/0/.../clip.mp4` produces a schemeless URI that never loads, so
/// downloaded videos have to go through the file constructor.
VideoPlayerController createLocalVideoController(String filePath) {
  return VideoPlayerController.file(File(filePath));
}

bool localPlaybackSupported(String filePath) => File(filePath).existsSync();
