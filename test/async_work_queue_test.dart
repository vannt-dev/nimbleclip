import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/services/async_work_queue.dart';

void main() {
  test('caps concurrency and starts pending work as slots open', () async {
    final completers = <int, Completer<void>>{};
    final started = <int>[];
    var running = 0;
    var maximumRunning = 0;
    final queue = AsyncWorkQueue<int>(
      maxConcurrent: 2,
      worker: (item) async {
        started.add(item);
        running++;
        maximumRunning = running > maximumRunning ? running : maximumRunning;
        final completer = Completer<void>();
        completers[item] = completer;
        await completer.future;
        running--;
      },
    );

    for (var item = 1; item <= 4; item++) {
      queue.add(item);
    }
    await Future<void>.delayed(Duration.zero);
    expect(started, [1, 2]);
    expect(queue.pending, 2);

    completers[1]!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(started, [1, 2, 3]);
    expect(maximumRunning, 2);

    completers[2]!.complete();
    completers[3]!.complete();
    await Future<void>.delayed(Duration.zero);
    completers[4]!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(queue.running, 0);
  });

  test('removes pending work and reacts to a higher limit', () async {
    final blockers = <int, Completer<void>>{};
    final started = <int>[];
    final queue = AsyncWorkQueue<int>(
      maxConcurrent: 1,
      worker: (item) async {
        started.add(item);
        final blocker = Completer<void>();
        blockers[item] = blocker;
        await blocker.future;
      },
    );

    queue
      ..add(1)
      ..add(2)
      ..add(3)
      ..removeWhere((item) => item == 2);
    queue.maxConcurrent = 2;
    await Future<void>.delayed(Duration.zero);

    expect(started, [1, 3]);
    for (final blocker in blockers.values) {
      blocker.complete();
    }
  });
}
