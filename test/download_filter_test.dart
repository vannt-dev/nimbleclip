import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/models/video_metadata.dart' show MediaKind;
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/views/downloads/download_filter.dart';

DownloadTask _task(
  String id,
  String title, {
  MediaKind kind = MediaKind.video,
}) {
  return DownloadTask(
    id: id,
    videoId: id,
    title: title,
    author: 'Creator',
    thumbnailUrl: '',
    downloadUrl: 'https://cdn.example.com/$id',
    originalUrl: 'https://example.com/$id',
    platform: VideoPlatform.facebook,
    qualityLabel: 'HD 720p',
    kind: kind,
    status: DownloadStatus.completed,
  );
}

void main() {
  final lesson = _task('lesson', 'Học Tiếng Việt cơ bản');
  final song = _task('song', 'Bài hát mùa thu', kind: MediaKind.audio);
  final photo = _task('photo', 'Sunset at Đà Lạt', kind: MediaKind.image);
  final trailer = _task('trailer', 'Movie TRAILER 2026');
  final tasks = [lesson, song, photo, trailer];

  test('an empty filter keeps every task in order', () {
    const filter = DownloadFilter();
    expect(filter.isActive, isFalse);
    expect(filter.apply(tasks), tasks);
  });

  test('a query matches titles without accents or case', () {
    expect(const DownloadFilter(query: 'tieng viet').apply(tasks), [lesson]);
    expect(const DownloadFilter(query: 'TIẾNG').apply(tasks), [lesson]);
    expect(const DownloadFilter(query: 'da lat').apply(tasks), [photo]);
    expect(const DownloadFilter(query: 'trailer').apply(tasks), [trailer]);
  });

  test('every word of the query must appear, in any order', () {
    expect(const DownloadFilter(query: 'viet hoc').apply(tasks), [lesson]);
    expect(const DownloadFilter(query: 'viet trailer').apply(tasks), isEmpty);
  });

  test('a blank query is no filter', () {
    const filter = DownloadFilter(query: '   ');
    expect(filter.isActive, isFalse);
    expect(filter.apply(tasks), tasks);
  });

  test('a type keeps only tasks of that kind', () {
    expect(const DownloadFilter(type: DownloadTypeFilter.video).apply(tasks), [
      lesson,
      trailer,
    ]);
    expect(const DownloadFilter(type: DownloadTypeFilter.audio).apply(tasks), [
      song,
    ]);
    expect(const DownloadFilter(type: DownloadTypeFilter.image).apply(tasks), [
      photo,
    ]);
  });

  test('a query and a type combine', () {
    const filter = DownloadFilter(
      query: 'mua thu',
      type: DownloadTypeFilter.video,
    );
    expect(filter.isActive, isTrue);
    expect(filter.apply(tasks), isEmpty);
    expect(filter.copyWith(type: DownloadTypeFilter.audio).apply(tasks), [
      song,
    ]);
  });

  test('a filter over a long list stays quick', () {
    final many = [
      for (var i = 0; i < 5000; i++)
        _task('t$i', i.isEven ? 'Video số $i' : 'Bài hát $i'),
    ];
    const filter = DownloadFilter(query: 'so 4');
    // Folded titles are reused across keystrokes.
    filter.apply(many);
    final watch = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      filter.apply(many);
    }
    watch.stop();
    expect(watch.elapsedMilliseconds, lessThan(500));
  });
}
