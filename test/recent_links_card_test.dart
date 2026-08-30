import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/models/analysis_history_entry.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/providers/analysis_history_provider.dart';
import 'package:nimble_clip/views/home/widgets/recent_links_card.dart';

/// Five links laid out flat pushed the result down the page, so the section is
/// closed until it is wanted.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  List<AnalysisHistoryEntry> entriesOf(int count) => [
    for (var index = 0; index < count; index++)
      AnalysisHistoryEntry.fromMetadata(
        analyzedAt: DateTime(2026, 8, 30, 12, index),
        VideoMetadata(
          id: 'post-$index',
          originalUrl: 'https://example.com/post-$index',
          title: 'Post $index',
          author: 'Creator',
          coverUrl: '',
          platform: VideoPlatform.facebook,
          qualities: const [],
        ),
      ),
  ];

  Widget host(
    List<AnalysisHistoryEntry> entries, {
    void Function(String)? on,
  }) => ChangeNotifierProvider(
    create: (_) => AnalysisHistoryProvider(),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: RecentLinksCard(entries: entries, onReplay: on ?? (_) {}),
      ),
    ),
  );

  testWidgets('the links are collapsed until the section is opened', (
    tester,
  ) async {
    await tester.pumpWidget(host(entriesOf(3)));
    await tester.pump();

    expect(find.text('Recent links (3)'), findsOneWidget);
    expect(find.text('Post 0'), findsNothing);

    await tester.tap(find.text('Recent links (3)'));
    await tester.pumpAndSettle();

    expect(find.text('Post 0'), findsOneWidget);
  });

  testWidgets('clearing is only reachable once the section is open', (
    tester,
  ) async {
    await tester.pumpWidget(host(entriesOf(3)));
    await tester.pump();

    // Out of reach while collapsed, so it cannot be hit for a list nobody can
    // see.
    expect(find.text('Clear'), findsNothing);

    await tester.tap(find.text('Recent links (3)'));
    await tester.pumpAndSettle();

    expect(find.text('Clear'), findsOneWidget);
  });

  testWidgets('an entry can be copied without replaying it', (tester) async {
    String? replayed;
    final copied = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(host(entriesOf(2), on: (url) => replayed = url));
    await tester.pump();
    await tester.tap(find.text('Recent links (2)'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.copy_rounded).first);
    await tester.pump();

    expect(copied, ['https://example.com/post-0']);
    expect(
      replayed,
      isNull,
      reason: 'copying must not re-run the analysis as a tap does',
    );
  });

  testWidgets('only the five most recent are listed', (tester) async {
    await tester.pumpWidget(host(entriesOf(8)));
    await tester.pump();

    expect(find.text('Recent links (5)'), findsOneWidget);

    await tester.tap(find.text('Recent links (5)'));
    await tester.pumpAndSettle();

    expect(find.text('Post 4'), findsOneWidget);
    expect(find.text('Post 5'), findsNothing);
  });
}
