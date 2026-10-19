import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'perf_scroll_test.dart' show openDownloads;

/// Memory over a long session: scroll the Downloads history, switch tabs, again and again, and
/// record the resident set size every 30 seconds. Steady after the warm-up is fine; a figure that
/// keeps climbing is a leak. Run like perf_scroll_test.dart, with
/// --target=integration_test/perf_longrun_test.dart (and --dart-define=PERF_MINUTES=10, the default).
/// The samples land in build/integration_response_data.json under "memory". With
/// --driver=test_driver/perf_memory_driver.dart the host also records the Dart heap after a
/// forced garbage collection every 30 s ("dart_heap"): flat there means the app keeps nothing
/// alive, and any growth in the resident size comes from the engine or the device.
const minutes = int.fromEnvironment('PERF_MINUTES', defaultValue: 10);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a long session: the memory settles instead of growing', (
    tester,
  ) async {
    await openDownloads(tester);
    final tabs = find.byType(NavigationDestination);
    final samples = <Map<String, Object>>[];
    final clock = Stopwatch()..start();
    var nextSample = Duration.zero;
    var rounds = 0;

    while (clock.elapsed < const Duration(minutes: minutes)) {
      if (clock.elapsed >= nextSample) {
        samples.add({
          'seconds': clock.elapsed.inSeconds,
          'rss_mb': ProcessInfo.currentRss / (1 << 20),
          'rounds': rounds,
        });
        nextSample += const Duration(seconds: 30);
      }
      final list = find.byType(ListView).first;
      for (var i = 0; i < 3; i++) {
        await tester.fling(list, const Offset(0, -900), 3000);
        await tester.pumpAndSettle();
      }
      for (var i = 0; i < 3; i++) {
        await tester.fling(list, const Offset(0, 900), 3000);
        await tester.pumpAndSettle();
      }
      for (final tab in [0, 2, 1]) {
        await tester.tap(tabs.at(tab));
        await tester.pumpAndSettle();
      }
      rounds++;
    }
    samples.add({
      'seconds': clock.elapsed.inSeconds,
      'rss_mb': ProcessInfo.currentRss / (1 << 20),
      'rounds': rounds,
    });
    binding.reportData = {
      'memory': samples,
      'max_rss_mb': ProcessInfo.maxRss / (1 << 20),
    };
  }, timeout: const Timeout(Duration(minutes: minutes + 5)));
}
