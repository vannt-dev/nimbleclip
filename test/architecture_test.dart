import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source files under `lib/`, grouped by the top-level directory they live in.
Map<String, List<File>> _sourcesByLayer() {
  final layers = <String, List<File>>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll(r'\', '/');
    // Generated localizations are not hand-written and are exempt.
    if (path.startsWith('lib/l10n/generated/')) continue;
    final relative = path.substring('lib/'.length);
    final layer = relative.contains('/')
        ? relative.substring(0, relative.indexOf('/'))
        : '.';
    (layers[layer] ??= []).add(entity);
  }
  return layers;
}

List<String> _importsOf(File file) => file
    .readAsLinesSync()
    .where((line) => line.trimLeft().startsWith('import '))
    .toList();

void _expectNoImports({
  required List<File> files,
  required List<String> forbidden,
  required String rule,
}) {
  final violations = <String>[];
  for (final file in files) {
    for (final import in _importsOf(file)) {
      for (final needle in forbidden) {
        if (import.contains(needle)) {
          violations.add('  ${file.path}: ${import.trim()}');
        }
      }
    }
  }
  expect(violations, isEmpty, reason: '$rule\n${violations.join('\n')}');
}

void main() {
  final layers = _sourcesByLayer();

  test('the source tree was actually found', () {
    // Guards against the whole suite passing vacuously if the working
    // directory or the layout ever changes.
    expect(layers['models'], isNotEmpty);
    expect(layers['services'], isNotEmpty);
    expect(layers['views'], isNotEmpty);
  });

  test('the lower layers do not depend on the upper ones', () {
    _expectNoImports(
      files: [...?layers['services'], ...?layers['models'], ...?layers['core']],
      forbidden: ['views/', 'providers/'],
      rule: 'services, models and core must not import views or providers.',
    );
  });

  test('domain models carry no presentation dependency', () {
    // `package:flutter/foundation.dart` is allowed and used: DownloadTask is a
    // ChangeNotifier. It carries no widgets, rendering or theming. `material`
    // is what drags presentation into a domain type.
    _expectNoImports(
      files: layers['models'] ?? [],
      forbidden: ['package:flutter/material.dart', 'app_localizations'],
      rule: 'models must not import material or the generated localizations.',
    );
  });

  test('the extractor layer carries no localizations', () {
    // Extractors describe an option with a QualityDescriptor and report a
    // failure with an ExtractionFailure; both are turned into text by the
    // caller. Nothing in the layer should need a locale.
    final extractors = [
      ...?layers['services'],
    ].where((file) => file.path.replaceAll(r'\', '/').contains('/extractors/'));
    expect(extractors, isNotEmpty);
    _expectNoImports(
      files: extractors.toList(),
      forbidden: ['app_localizations'],
      rule: 'lib/services/extractors/ must not import the localizations.',
    );
  });
}
