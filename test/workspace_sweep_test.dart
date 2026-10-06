import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/providers/download_provider.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('sweep_test'));
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  Directory workspace(DateTime madeAt) {
    final directory = Directory(
      '${temp.path}/slideshow_${madeAt.microsecondsSinceEpoch}',
    )..createSync();
    File('${directory.path}/video.stream').writeAsStringSync('segments');
    return directory;
  }

  test('removes what an earlier run left, with everything in it', () async {
    final launch = DateTime(2026, 10, 6, 12);
    final left = workspace(launch.subtract(const Duration(hours: 3)));
    final older = workspace(launch.subtract(const Duration(days: 9)));

    final removed = await sweepLeftoverWorkspaces(temp, createdBefore: launch);

    expect(removed, 2);
    expect(left.existsSync(), isFalse);
    expect(older.existsSync(), isFalse);
  });

  test('leaves the scratch of this run alone', () async {
    final launch = DateTime(2026, 10, 6, 12);
    final own = workspace(launch.add(const Duration(seconds: 2)));

    final removed = await sweepLeftoverWorkspaces(temp, createdBefore: launch);

    expect(removed, 0);
    expect(own.existsSync(), isTrue);
  });

  test('touches nothing that is not its own', () async {
    final launch = DateTime(2026, 10, 6, 12);
    final other = Directory('${temp.path}/image_cache')..createSync();
    final unnumbered = Directory('${temp.path}/slideshow_keep')..createSync();
    final file = File('${temp.path}/slideshow_1')..writeAsStringSync('a file');

    final removed = await sweepLeftoverWorkspaces(temp, createdBefore: launch);

    expect(removed, 0);
    expect(other.existsSync(), isTrue);
    expect(unnumbered.existsSync(), isTrue);
    expect(file.existsSync(), isTrue);
  });

  test('is quiet when there is no temp directory', () async {
    final missing = Directory('${temp.path}/gone');

    expect(
      await sweepLeftoverWorkspaces(missing, createdBefore: DateTime.now()),
      0,
    );
  });
}
