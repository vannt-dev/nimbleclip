import 'dart:async';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/common.dart';
import 'package:integration_test/integration_test_driver.dart';

/// Driver for perf_longrun_test.dart that also samples the Dart heap from the host: every 30 s
/// it forces a garbage collection and records what is still in use. A heap that stays flat after
/// collection means the app holds nothing it should have let go. The samples are added to
/// build/integration_response_data.json under "dart_heap".
Future<void> main() async {
  final driver = await FlutterDriver.connect();
  final isolateId = driver.appIsolate.id!;
  final clock = Stopwatch()..start();
  final samples = <Map<String, Object?>>[];

  Future<void> sample() async {
    final profile = await driver.serviceClient.getAllocationProfile(
      isolateId,
      gc: true,
    );
    final usage = profile.memoryUsage;
    samples.add({
      'seconds': clock.elapsed.inSeconds,
      'heap_mb': (usage?.heapUsage ?? 0) / (1 << 20),
      'external_mb': (usage?.externalUsage ?? 0) / (1 << 20),
    });
  }

  await sample();
  final timer = Timer.periodic(const Duration(seconds: 30), (_) => sample());
  final result = await driver.requestData(
    null,
    timeout: const Duration(minutes: 30),
  );
  timer.cancel();
  await sample();
  await driver.close();

  final response = Response.fromJson(result);
  await writeResponseData({...?response.data, 'dart_heap': samples});
  if (!response.allTestsPassed) {
    throw Exception('Failed: ${response.formattedFailureDetails}');
  }
}
