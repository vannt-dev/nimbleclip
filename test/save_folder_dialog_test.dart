import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/providers/settings_provider.dart';
import 'package:nimble_clip/views/settings/save_folder_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory.systemTemp.path,
        );
  });

  Future<SettingsProvider> openDialog(WidgetTester tester) async {
    final settings = (await tester.runAsync(() async {
      final provider = SettingsProvider();
      await provider.initialized;
      return provider;
    }))!;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => SaveFolderDialog(settings: settings),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return settings;
  }

  testWidgets('a name with a path separator is refused in place', (
    tester,
  ) async {
    final settings = await openDialog(tester);

    await tester.enterText(
      find.byKey(const ValueKey('saveFolderField')),
      'a/b',
    );
    await tester.pump();

    expect(find.textContaining('cannot contain'), findsOneWidget);
    final save = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(save.onPressed, isNull);
    expect(settings.saveFolderName, isNull);
  });

  testWidgets('a valid name is saved and closes the dialog', (tester) async {
    final settings = await openDialog(tester);

    await tester.enterText(
      find.byKey(const ValueKey('saveFolderField')),
      ' Clips ',
    );
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byType(ElevatedButton));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(settings.saveFolderName, 'Clips');
    expect(find.byType(SaveFolderDialog), findsNothing);
  });
}
