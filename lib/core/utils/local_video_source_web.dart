import 'package:video_player/video_player.dart';

/// On Web the browser owns the downloaded file — the app never has a readable
/// path to it, so local playback is not offered.
VideoPlayerController createLocalVideoController(String filePath) {
  throw UnsupportedError(
    'Local files cannot be played in the browser. Open the file from your '
    'browser download manager instead.',
  );
}

bool localPlaybackSupported(String filePath) => false;
