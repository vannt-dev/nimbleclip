import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/providers/analysis_history_provider.dart';
import 'package:nimble_clip/providers/download_provider.dart';
import 'package:nimble_clip/providers/settings_provider.dart';
import 'package:nimble_clip/providers/shared_intent_provider.dart';
import 'package:nimble_clip/providers/video_extractor_provider.dart';
import 'package:nimble_clip/views/downloads/downloads_screen.dart';
import 'package:nimble_clip/views/home/home_screen.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/services/extractors/base_extractor.dart';
import 'package:nimble_clip/services/extractors/extraction_failure.dart';
import 'package:nimble_clip/services/extractors/registry.dart';
import 'package:nimble_clip/views/main_navigation_screen.dart';

import 'support/inert_download_service.dart';

/// Keeps the network out of a test about which tab is showing. The home screen
/// analyses whatever it is handed, and a real attempt outlives the test that
/// started it, which showed up as unrelated failures in the next one.
class _InertExtractorRegistry extends ExtractorRegistry {
  @override
  Future<VideoMetadata> extract(String rawUrl) async {
    throw ExtractionException(
      const ExtractionFailure(ExtractionFailureKind.invalidLink),
    );
  }
}

/// A share arriving while another tab is open used to be analysed on the home
/// tab without bringing it forward, so the reader watched an unchanged
/// downloads list and concluded the share had done nothing.
void main() {
  const channel = MethodChannel('com.vannt.nimbleclip/shared_intent');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  /// Makes the platform hand over [text] the next time the app asks for a
  /// pending share, which is what a real share does on resume.
  void queueSharedText(String? text) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return call.method == 'consumeSharedText' ? text : null;
        });
  }

  Widget host() => MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ChangeNotifierProvider(
        create: (_) => VideoExtractorProvider(
          extractorRegistry: _InertExtractorRegistry(),
        ),
      ),
      ChangeNotifierProvider(create: (_) => AnalysisHistoryProvider()),
      ChangeNotifierProvider(create: (_) => SharedIntentProvider()),
      ChangeNotifierProvider(
        create: (_) =>
            DownloadProvider(downloadService: InertDownloadService()),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const MainNavigationScreen(),
    ),
  );

  testWidgets('a shared link brings the home tab forward', (tester) async {
    queueSharedText(null);
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pumpAndSettle();
    expect(
      _visibleTab(tester),
      DownloadsScreen,
      reason: 'the downloads tab should be showing before the share arrives',
    );

    queueSharedText('https://www.facebook.com/share/AbCdEf/');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(_visibleTab(tester), HomeScreen);
  });

  testWidgets('a tab the reader chose is left alone without a share', (
    tester,
  ) async {
    queueSharedText(null);
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pumpAndSettle();

    // A resume with nothing shared must not yank them off the tab they picked.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(_visibleTab(tester), DownloadsScreen);
  });
}

/// The type of the screen [IndexedStack] is currently showing.
Type _visibleTab(WidgetTester tester) {
  final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
  return stack.children[stack.index!].runtimeType;
}
