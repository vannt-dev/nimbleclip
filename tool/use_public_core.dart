// Puts the public core where the app expects its core, for a checkout without
// access to the private one.
//
//   dart run tool/use_public_core.dart
//
// The app is written against `lib/services/extractors`, which is a git
// submodule of a private repository. Without access that folder is empty and
// nothing builds. This copies `lib/services/extractors_public` (one extractor
// for direct media links and pages with Open Graph metadata, and stand-ins for
// the rest) into it. Git does not look inside a submodule's folder that was
// never checked out, so the copy never shows up as a change.
//
// Run it again after pulling, to pick up changes to the public core. It
// refuses to touch a folder that holds the private core.
import 'dart:io';

const _target = 'lib/services/extractors';
const _source = 'lib/services/extractors_public';
const _marker = '.public_core';

void main() {
  final source = Directory(_source);
  if (!source.existsSync()) {
    stderr.writeln(
      'Run this from the root of the repository: $_source is not here.',
    );
    exitCode = 2;
    return;
  }

  final marker = File('$_target/$_marker');
  final hasCore = File('$_target/registry.dart').existsSync();
  if (hasCore && !marker.existsSync()) {
    stderr.writeln(
      '$_target holds the private core (or files this script did not put there). '
      'Nothing was changed.',
    );
    exitCode = 1;
    return;
  }

  // Only what an earlier run wrote is ever removed.
  if (marker.existsSync()) {
    for (final line in marker.readAsLinesSync()) {
      final file = File('$_target/$line');
      if (line.isNotEmpty && file.existsSync()) file.deleteSync();
    }
  }

  final copied = <String>[];
  for (final entity in source.listSync(recursive: true)) {
    if (entity is! File) continue;
    final relative = entity.path
        .substring(source.path.length + 1)
        .replaceAll(r'\', '/');
    if (relative == 'README.md') continue;
    final destination = File('$_target/$relative')
      ..parent.createSync(recursive: true);
    entity.copySync(destination.path);
    copied.add(relative);
  }
  marker
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('${copied.join('\n')}\n');

  stdout.writeln('Public core in place: ${copied.length} files in $_target.');
  stdout.writeln(
    'It reads direct media links and pages with Open Graph metadata. YouTube, '
    'TikTok and the other sites NimbleClip knows by name need the full core.',
  );
}
