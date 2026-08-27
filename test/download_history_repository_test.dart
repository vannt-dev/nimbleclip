import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/models/video_metadata.dart' show MediaKind;
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/services/download_history_repository.dart';

Map<String, dynamic> receipt(String id) => DownloadTask(
  id: id,
  videoId: 'video-$id',
  title: 'Clip $id',
  author: 'Creator',
  thumbnailUrl: '',
  downloadUrl: 'https://cdn.example.com/$id.mp4',
  originalUrl: 'https://example.com/$id',
  platform: VideoPlatform.facebook,
  qualityLabel: 'HD 720p',
  format: 'mp4',
  kind: MediaKind.video,
  status: DownloadStatus.completed,
  filePath: '/downloads/$id.mp4',
).toJson();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('serves receipts from memory instead of re-reading preferences', () async {
    final repository = SharedPreferencesDownloadHistoryRepository();
    await repository.saveDownloadReceipt(receipt('a'));

    // Clear the backing store behind the repository's back. A repository that
    // re-reads preferences on every call would now report nothing; the cache is
    // what makes the saved receipt survive.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('download_receipts_list');

    final loaded = await repository.loadDownloadReceipts();
    expect(loaded.single.id, 'a');
  });

  test('persists every saved receipt to preferences', () async {
    final repository = SharedPreferencesDownloadHistoryRepository();
    await repository.saveDownloadReceipt(receipt('a'));
    await repository.saveDownloadReceipt(receipt('b'));

    final prefs = await SharedPreferences.getInstance();
    final stored =
        jsonDecode(prefs.getString('download_receipts_list')!) as List<dynamic>;
    expect(stored.map((entry) => entry['id']), containsAll(['a', 'b']));
  });

  test(
    'replaces a receipt with the same id rather than duplicating it',
    () async {
      final repository = SharedPreferencesDownloadHistoryRepository();
      await repository.saveDownloadReceipt(receipt('a'));
      await repository.saveDownloadReceipt({
        ...receipt('a'),
        'filePath': '/downloads/moved.mp4',
      });

      final loaded = await repository.loadDownloadReceipts();
      expect(loaded, hasLength(1));
      expect(loaded.single.filePath, '/downloads/moved.mp4');
    },
  );

  test('reads receipts written by a previous run', () async {
    SharedPreferences.setMockInitialValues({
      'download_receipts_list': jsonEncode([receipt('old')]),
    });

    final repository = SharedPreferencesDownloadHistoryRepository();
    final loaded = await repository.loadDownloadReceipts();
    expect(loaded.single.id, 'old');
  });

  test(
    'removing a receipt takes it out of both memory and preferences',
    () async {
      final repository = SharedPreferencesDownloadHistoryRepository();
      await repository.saveDownloadReceipts([receipt('a'), receipt('b')]);
      await repository.removeDownloadReceipts({'a'});

      expect(
        (await repository.loadDownloadReceipts()).map((entry) => entry.id),
        ['b'],
      );
      final prefs = await SharedPreferences.getInstance();
      final stored =
          jsonDecode(prefs.getString('download_receipts_list')!)
              as List<dynamic>;
      expect(stored.map((entry) => entry['id']), ['b']);
    },
  );

  test('caps the receipt store so it cannot grow without bound', () async {
    final repository = SharedPreferencesDownloadHistoryRepository();
    await repository.saveDownloadReceipts([
      for (var index = 0; index < 520; index++) receipt('id-$index'),
    ]);

    final loaded = await repository.loadDownloadReceipts();
    expect(loaded, hasLength(500));
  });

  test('history round trips through preferences', () async {
    final repository = SharedPreferencesDownloadHistoryRepository();
    await repository.saveHistory([receipt('a'), receipt('b')]);

    final loaded = await repository.loadHistory();
    expect(loaded.map((task) => task.id), ['a', 'b']);
  });

  test('a corrupt store reads as empty rather than throwing', () async {
    SharedPreferences.setMockInitialValues({
      'download_receipts_list': 'not json at all',
      'download_history_list': '{"not":"a list"}',
    });

    final repository = SharedPreferencesDownloadHistoryRepository();
    expect(await repository.loadDownloadReceipts(), isEmpty);
    expect(await repository.loadHistory(), isEmpty);
  });
}
