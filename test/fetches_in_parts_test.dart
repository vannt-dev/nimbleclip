import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/services/background_download_service.dart';

DownloadTask _task({
  required VideoPlatform platform,
  required MediaKind kind,
  required String url,
}) => DownloadTask(
  id: 'task',
  videoId: 'v1',
  title: 'A title',
  author: '',
  thumbnailUrl: '',
  downloadUrl: url,
  originalUrl: 'https://example.com/watch?v=1',
  platform: platform,
  qualityLabel: 'Original',
  format: kind == MediaKind.audio ? 'm4a' : 'mp4',
  kind: kind,
);

/// Only the file YouTube holds back when it is asked for whole is fetched a
/// range at a time; everything else stays one transfer, which can resume
/// mid-file.
void main() {
  const stream =
      'https://rr3---sn-8qj-nboel.googlevideo.com/videoplayback?itag=140';

  test('a YouTube audio stream is fetched in parts', () {
    expect(
      BackgroundDownloadService.fetchesInParts(
        _task(
          platform: VideoPlatform.youtube,
          kind: MediaKind.audio,
          url: stream,
        ),
      ),
      isTrue,
    );
  });

  test('everything else is one transfer', () {
    // YouTube's 360p file with picture and sound is served at full speed whole.
    expect(
      BackgroundDownloadService.fetchesInParts(
        _task(
          platform: VideoPlatform.youtube,
          kind: MediaKind.video,
          url: stream.replaceFirst('itag=140', 'itag=18'),
        ),
      ),
      isFalse,
    );
    expect(
      BackgroundDownloadService.fetchesInParts(
        _task(
          platform: VideoPlatform.soundcloud,
          kind: MediaKind.audio,
          url: 'https://cf-media.sndcdn.com/track.mp3',
        ),
      ),
      isFalse,
    );
    // Audio of a YouTube link that is not served from YouTube's stream hosts.
    expect(
      BackgroundDownloadService.fetchesInParts(
        _task(
          platform: VideoPlatform.youtube,
          kind: MediaKind.audio,
          url: 'https://googlevideo.com.example.org/audio.m4a',
        ),
      ),
      isFalse,
    );
  });
}
