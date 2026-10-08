import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Licences of native code the app carries that no Dart package declares.
///
/// Flutter's licence page lists the packages from `pubspec.yaml` by itself.
/// LAME, the MP3 encoder, is C source built into the Android app, so nothing
/// would mention it: its licence (LGPL) asks for the text to travel with the
/// binary, and this is where a user of the app can read it.
const lameLicenceAsset = 'assets/licenses/lame-COPYING.txt';

bool _registered = false;

void registerBundledLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'LAME (libmp3lame)',
    ], await rootBundle.loadString(lameLicenceAsset));
  });
}
