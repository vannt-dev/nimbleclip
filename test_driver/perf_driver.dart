import 'package:integration_test/integration_test_driver.dart';

/// Driver for the perf tests in integration_test/: writes what they report
/// (frame timings, memory samples) to build/integration_response_data.json.
Future<void> main() => integrationDriver();
