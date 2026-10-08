import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/core/utils/bundled_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the licence page carries the licence of the MP3 encoder', () async {
    registerBundledLicenses();
    // Asking twice must not list it twice.
    registerBundledLicenses();

    final lame = await LicenseRegistry.licenses
        .where((entry) => entry.packages.contains('LAME (libmp3lame)'))
        .toList();

    expect(lame, hasLength(1));
    final text = lame.single.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('GNU LIBRARY GENERAL PUBLIC LICENSE'));
    expect(text, contains('Version 2, June 1991'));
  });

  test('the bundled text is the one that came with the LAME source', () {
    // The asset is a copy, so that the build does not reach into android/.
    // If LAME is ever updated, the two have to move together.
    String normalised(String path) =>
        File(path).readAsStringSync().replaceAll('\r\n', '\n');
    expect(
      normalised(lameLicenceAsset),
      normalised('android/app/src/main/cpp/lame/COPYING'),
    );
  });
}
