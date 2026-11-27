import 'core/utils/external_service_policy.dart';
import 'providers/analysis_history_provider.dart';
import 'providers/download_provider.dart';
import 'providers/quick_download_coordinator.dart';
import 'providers/settings_provider.dart';
import 'providers/shared_intent_provider.dart';
import 'services/extractors/registry.dart';
import 'services/quick_share_channel.dart';

/// The app's long-lived state, made before any widget.
///
/// Quick download can start the app with no screen, and then no widget is
/// ever built: the providers the widget tree would make on first use have to
/// exist already for a shared link to be downloaded.
class AppServices {
  AppServices({
    QuickShareChannel quickShare = const PlatformQuickShareChannel(),
  }) : extractionPolicy = ExtractionPolicy() {
    // Built once: the registry holds the policy by reference and every
    // extractor reads `allowExternalServices` at call time, so toggling the
    // setting already takes effect.
    extractorRegistry = ExtractorRegistry(
      externalServiceAccess: extractionPolicy,
    );
    settings = SettingsProvider(
      extractionPolicy: extractionPolicy,
      quickShare: quickShare,
    );
    analysisHistory = AnalysisHistoryProvider();
    sharedIntent = SharedIntentProvider();
    downloads = DownloadProvider(extractorRegistry: extractorRegistry);
    // What the widget tree's proxy provider does on each settings change,
    // here without a tree to run it.
    settings.addListener(() => applyDownloadSettings(settings, downloads));
    applyDownloadSettings(settings, downloads);
    quickDownloads = QuickDownloadCoordinator(
      channel: quickShare,
      settings: settings,
      downloads: downloads,
      extractorRegistry: extractorRegistry,
      history: analysisHistory,
    )..start();
  }

  final ExtractionPolicy extractionPolicy;
  late final ExtractorRegistry extractorRegistry;
  late final SettingsProvider settings;
  late final AnalysisHistoryProvider analysisHistory;
  late final SharedIntentProvider sharedIntent;
  late final DownloadProvider downloads;
  late final QuickDownloadCoordinator quickDownloads;
}

/// Hands the settings the download list reads to it.
DownloadProvider applyDownloadSettings(
  SettingsProvider settings,
  DownloadProvider downloads,
) => downloads
  ..maxConcurrentDownloads = settings.maxConcurrentDownloads
  ..wifiOnlyDownloads = settings.wifiOnlyDownloads
  ..convertAudioToMp3 = settings.convertAudioToMp3
  ..saveLyrics = settings.saveLyrics
  ..saveSubtitles = settings.saveSubtitles;
