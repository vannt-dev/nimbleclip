import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
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
      label: const Hd720(),
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
    expect(history.entries.first.title, 'Clip 21');
    expect(history.entries.last.title, 'Clip 2');

    await history.add(metadata(99, url: 'https://example.com/10'));
    expect(history.entries, hasLength(20));
    expect(history.entries.first.title, 'Clip 99');
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

  test('persists compact history without expiring media URLs', () async {
    final history = AnalysisHistoryProvider();
    await history.ready;
    await history.add(metadata(1));

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('analysis_history_v1')!;
    final stored = jsonDecode(raw) as List<dynamic>;
    final entry = stored.single as Map<String, dynamic>;

    expect(entry['url'], 'https://example.com/1');
    expect(entry['title'], 'Clip 1');
    expect(entry.containsKey('metadata'), isFalse);
    expect(raw, isNot(contains('downloadUrl')));
    expect(raw, isNot(contains('cdn.example.com')));
  });

  test('leaves an already compact store untouched on load', () async {
    // Key order is the observable proxy for "was not rewritten": `toJson`
    // always emits `url` first, so a title-first payload that survives the load
    // proves no save happened. Rewriting a store that needs no migration costs
    // a full re-encode and a preferences write on every app start.
    const seeded =
        '[{"title":"Clip 7","url":"https://example.com/7","coverUrl":"",'
        '"platform":"generic","analyzedAt":"2026-01-01T00:00:00.000"}]';
    SharedPreferences.setMockInitialValues({'analysis_history_v1': seeded});

    final history = AnalysisHistoryProvider();
    await history.ready;

    expect(history.entries.single.title, 'Clip 7');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('analysis_history_v1'), seeded);
  });

  test('migrates legacy full metadata to compact storage on load', () async {
    SharedPreferences.setMockInitialValues({
      'analysis_history_v1': jsonEncode([
        {
          'metadata': metadata(7).toJson(),
          'analyzedAt': DateTime(2026).toIso8601String(),
        },
      ]),
    });

    final history = AnalysisHistoryProvider();
    await history.ready;

    expect(history.entries.single.title, 'Clip 7');
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('analysis_history_v1')!;
    expect(raw, isNot(contains('metadata')));
    expect(raw, isNot(contains('downloadUrl')));
  });
}
