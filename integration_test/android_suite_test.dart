// The three Android suites in one file: `flutter test` builds and installs the
// app once per file it is given, and each build costs a minute or more on the
// CI emulator. Each suite keeps its own group, so a setUpAll at the root of one
// suite stays that suite's own.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'android_storage_test.dart' as android_storage;
import 'mp3_conversion_test.dart' as mp3_conversion;
import 'slideshow_render_test.dart' as slideshow_render;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('android_storage', android_storage.main);
  group('slideshow_render', slideshow_render.main);
  group('mp3_conversion', mp3_conversion.main);
}
