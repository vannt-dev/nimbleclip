import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'app_services.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'providers/download_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/video_extractor_provider.dart';
import 'providers/analysis_history_provider.dart';
import 'providers/shared_intent_provider.dart';
import 'core/utils/bundled_licenses.dart';
import 'core/utils/external_service_policy.dart';
import 'core/utils/image_cache_size.dart';
import 'services/extractors/registry.dart';
import 'l10n/generated/app_localizations.dart';
import 'views/main_navigation_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  configureImageCacheBudget();
  registerBundledLicenses();
  // Made before the first frame: an engine started by Quick download has no
  // screen and may never draw one, and its shared link still has to download.
  final services = AppServices();
  runApp(NimbleClipApp(services: services));
}

class NimbleClipApp extends StatelessWidget {
  const NimbleClipApp({super.key, this.services});

  /// The app's state made ahead of the tree. Without it, as in a test, the
  /// tree makes its own on first use.
  final AppServices? services;

  List<SingleChildWidget> _sharedProviders(AppServices services) => [
    ChangeNotifierProvider.value(value: services.extractionPolicy),
    Provider.value(value: services.extractorRegistry),
    ChangeNotifierProvider.value(value: services.settings),
    ChangeNotifierProvider.value(value: services.analysisHistory),
    ChangeNotifierProvider.value(value: services.sharedIntent),
    ChangeNotifierProvider(
      create: (_) =>
          VideoExtractorProvider(extractorRegistry: services.extractorRegistry),
    ),
    ChangeNotifierProvider.value(value: services.downloads),
  ];

  @override
  Widget build(BuildContext context) {
    final prebuilt = services;
    return MultiProvider(
      providers: prebuilt != null
          ? _sharedProviders(prebuilt)
          : [
              ChangeNotifierProvider(create: (_) => ExtractionPolicy()),
              // Built once: the registry holds the policy by reference and every
              // extractor reads `allowExternalServices` at call time, so toggling the
              // setting already takes effect. Rebuilding it per change would only
              // discard six fresh extractors that nothing downstream ever reads.
              Provider(
                create: (context) => ExtractorRegistry(
                  externalServiceAccess: context.read<ExtractionPolicy>(),
                ),
              ),
              ChangeNotifierProvider(
                create: (context) => SettingsProvider(
                  extractionPolicy: context.read<ExtractionPolicy>(),
                ),
              ),
              ChangeNotifierProvider(create: (_) => AnalysisHistoryProvider()),
              ChangeNotifierProvider(create: (_) => SharedIntentProvider()),
              ChangeNotifierProvider(
                create: (context) => VideoExtractorProvider(
                  extractorRegistry: context.read<ExtractorRegistry>(),
                ),
              ),
              ChangeNotifierProxyProvider<SettingsProvider, DownloadProvider>(
                create: (context) => DownloadProvider(
                  extractorRegistry: context.read<ExtractorRegistry>(),
                ),
                update: (context, settings, downloads) => applyDownloadSettings(
                  settings,
                  downloads ??
                      DownloadProvider(
                        extractorRegistry: context.read<ExtractorRegistry>(),
                      ),
                ),
              ),
            ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: AppConstants.appName,
            locale: settings.locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            debugShowCheckedModeBanner: false,
            themeMode: settings.themeMode,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            // Status bar icons follow the resolved theme. Setting them once at
            // startup left dark icons on a dark background in dark mode, and
            // never reacted to the system theme changing.
            builder: (context, child) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: isDark
                      ? Brightness.light
                      : Brightness.dark,
                  statusBarBrightness: isDark
                      ? Brightness.dark
                      : Brightness.light,
                  systemNavigationBarColor: Theme.of(
                    context,
                  ).scaffoldBackgroundColor,
                  systemNavigationBarIconBrightness: isDark
                      ? Brightness.light
                      : Brightness.dark,
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const MainNavigationScreen(),
          );
        },
      ),
    );
  }
}
