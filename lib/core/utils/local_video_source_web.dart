import 'package:video_player/video_player.dart';

/// On Web the browser owns the downloaded file — the app never has a readable
/// path to it, so local playback is not offered.
VideoPlayerController createLocalVideoController(String filePath) {
  throw UnsupportedError(
    'Không phát được file cục bộ trên trình duyệt. Hãy mở file bằng trình quản '
    'lý tải xuống của trình duyệt.',
  );
}

bool localPlaybackSupported(String filePath) => false;
