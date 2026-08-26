import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'providers/download_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/video_extractor_provider.dart';
import 'providers/analysis_history_provider.dart';
import 'providers/shared_intent_provider.dart';
import 'core/utils/external_service_policy.dart';
import 'services/extractors/registry.dart';
import 'l10n/generated/app_localizations.dart';
import 'views/main_navigation_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NimbleClipApp());
}

class NimbleClipApp extends StatelessWidget {
  const NimbleClipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ExtractionPolicy()),
        ProxyProvider<ExtractionPolicy, ExtractorRegistry>(
          update: (_, policy, _) =>
              ExtractorRegistry(externalServiceAccess: policy),
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
          update: (context, settings, downloads) {
            final provider =
                downloads ??
                DownloadProvider(
                  extractorRegistry: context.read<ExtractorRegistry>(),
                );
            provider.maxConcurrentDownloads = settings.maxConcurrentDownloads;
            return provider;
          },
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
