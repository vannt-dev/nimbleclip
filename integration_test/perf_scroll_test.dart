import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nimble_clip/core/constants/app_constants.dart';
import 'package:nimble_clip/main.dart' as app;
import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Scroll smoothness of the Downloads list with a long history.
///
/// Not part of the device suite: frame times only mean something in profile
/// mode, which `flutter test` does not run. Measure with
///
///   node tool/perf_thumbnail_server.js 8765 <a 640x360 JPEG> &   # thumbnails at http://10.0.2.2:8765/
///   flutter drive --profile --no-dds -d emulator-5554 \
///     --driver=test_driver/perf_driver.dart \
///     --target=integration_test/perf_scroll_test.dart \
///     --dart-define=PERF_THUMBNAIL_BASE=http://10.0.2.2:8765/
///
/// The frame build and raster times land in build/integration_response_data.json under
/// "downloads_scroll". `--no-dds` is needed: the timing reader connects to the VM service itself.
/// On an emulator the raster times go through the host's GPU emulation; compare runs with each
/// other, not with a phone.
/// Without PERF_THUMBNAIL_BASE the cards have no thumbnail.
const thumbnailBase = String.fromEnvironment('PERF_THUMBNAIL_BASE');
const historySize = int.fromEnvironment('PERF_HISTORY_SIZE', defaultValue: 300);

/// [count] finished downloads, as the history repository stores them.
String seededHistory(int count) {
  final now = DateTime.now();
  final platforms = VideoPlatform.values;
  final tasks = List.generate(count, (i) {
    final created = now.subtract(Duration(minutes: 7 * i));
    return DownloadTask(
      id: 'perf-$i',
      videoId: 'v$i',
      title: 'A downloaded video with a title long enough to wrap, number $i',
      author: 'Author ${i % 37}',
      thumbnailUrl: thumbnailBase.isEmpty ? '' : '${thumbnailBase}thumb-$i.jpg',
      downloadUrl: 'https://example.invalid/v$i.mp4',
      originalUrl: 'https://example.invalid/watch/$i',
      platform: platforms[i % platforms.length],
      qualityLabel: i.isEven ? '720p' : '1080p',
      status: DownloadStatus.completed,
      progress: 1,
      totalBytes: 12000000 + i * 1000,
      receivedBytes: 12000000 + i * 1000,
      filePath: '/storage/emulated/0/Movies/NimbleClip/perf-$i.mp4',
      createdAt: created,
      completedAt: created.add(const Duration(seconds: 40)),
    ).toJson();
  });
  return jsonEncode(tasks);
}

Future<void> openDownloads(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    AppConstants.keyDownloadHistory,
    seededHistory(historySize),
  );
  app.main();
  await tester.pumpAndSettle(const Duration(seconds: 2));
  await tester.tap(find.byType(NavigationDestination).at(1));
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Downloads: flinging through a long history', (tester) async {
    await openDownloads(tester);
    final list = find.byType(ListView).first;
    expect(list, findsOneWidget);

    await binding.watchPerformance(() async {
      for (var round = 0; round < 6; round++) {
        for (var i = 0; i < 4; i++) {
          await tester.fling(list, const Offset(0, -900), 3000);
          await tester.pumpAndSettle();
        }
        for (var i = 0; i < 4; i++) {
          await tester.fling(list, const Offset(0, 900), 3000);
          await tester.pumpAndSettle();
        }
      }
    }, reportKey: 'downloads_scroll');
  });
}
