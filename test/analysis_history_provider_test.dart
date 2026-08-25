import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/providers/analysis_history_provider.dart';

VideoMetadata metadata(int index, {String? url}) => VideoMetadata(
  id: '$index',
  originalUrl: url ?? 'https://example.com/$index',
  title: 'Clip $index',
  author: 'Creator',
  coverUrl: '',
  platform: VideoPlatform.generic,
  qualities: [
    VideoQualityOption.video(
      id: 'q$index',
      label: '720p',
      quality: '720p',
      format: 'mp4',
      downloadUrl: 'https://cdn.example.com/$index.mp4',
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('keeps the latest 20 analyses and de-duplicates by URL', () async {
    final history = AnalysisHistoryProvider();
    await history.ready;
    for (var index = 0; index < 22; index++) {
      await history.add(metadata(index));
    }
    expect(history.entries, hasLength(20));
    expect(history.entries.first.metadata.id, '21');
    expect(history.entries.last.metadata.id, '2');

    await history.add(metadata(99, url: 'https://example.com/10'));
    expect(history.entries, hasLength(20));
    expect(history.entries.first.metadata.id, '99');
    expect(
      history.entries.where(
        (entry) => entry.metadata.originalUrl == 'https://example.com/10',
      ),
      hasLength(1),
    );
  });

  test('restores persisted metadata and can clear it', () async {
    final first = AnalysisHistoryProvider();
    await first.ready;
    await first.add(metadata(1));

    final restored = AnalysisHistoryProvider();
    await restored.ready;
    expect(restored.entries.single.metadata.title, 'Clip 1');
    await restored.clear();

    final empty = AnalysisHistoryProvider();
    await empty.ready;
    expect(empty.entries, isEmpty);
  });
}
