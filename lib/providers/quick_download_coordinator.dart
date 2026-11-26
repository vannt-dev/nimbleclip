import 'dart:async';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart' show debugPrint;

import '../core/utils/url_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/download_task.dart';
import '../models/video_metadata.dart';
import '../services/extractors/registry.dart';
import '../services/extractors/youtube_playlist.dart';
import '../services/quick_share_channel.dart';
import 'analysis_history_provider.dart';
import 'download_provider.dart';
import 'settings_provider.dart';
import 'video_extractor_provider.dart';

/// What became of one link shared to Quick download.
enum QuickDownloadOutcome {
  /// The shared text held no link.
  noLink,

  /// A playlist: which of its videos to take is a question for the app.
  needsApp,

  /// The link could not be read.
  unreadable,

  /// The same media was already downloaded, so nothing was started.
  alreadySaved,

  /// The same media is already downloading.
  alreadyRunning,

  /// Started, and held back until the device is on Wi-Fi.
  waitingForWifi,

  /// Started; it carries on in the downloads list.
  started,

  /// Downloaded and saved.
  saved,

  /// Started, then failed.
  failed,
}

/// Downloads links shared to Quick download, with no screen.
///
/// Works on the app's own download list, settings and history, so whatever it
/// starts shows in Downloads when the app is opened. It reads no widget and
/// waits for no frame: it runs in an engine that may have no screen at all.
/// What happens is told through the platform's own messages.
class QuickDownloadCoordinator {
  QuickDownloadCoordinator({
    required this._channel,
    required this._settings,
    required this._downloads,
    required ExtractorRegistry extractorRegistry,
    this._history,
    Locale Function()? deviceLocale,
    this._completionLimit = const Duration(hours: 2),
  }) : _registry = extractorRegistry,
       _deviceLocale = deviceLocale ?? _platformLocale;

  final QuickShareChannel _channel;
  final SettingsProvider _settings;
  final DownloadProvider _downloads;
  final ExtractorRegistry _registry;
  final AnalysisHistoryProvider? _history;
  final Locale Function() _deviceLocale;

  /// How long the process is kept for one download to finish. A ceiling, so
  /// a transfer that never reports back cannot hold it for good.
  final Duration _completionLimit;
  StreamSubscription<String>? _subscription;

  static Locale _platformLocale() => PlatformDispatcher.instance.locale;

  void start() {
    _subscription ??= _channel.shares.listen((text) => unawaited(handle(text)));
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// The app's language, as the screens would pick it.
  AppLocalizations _l10n() {
    final chosen = _settings.locale ?? _deviceLocale();
    final supported = AppLocalizations.supportedLocales.any(
      (locale) => locale.languageCode == chosen.languageCode,
    );
    return lookupAppLocalizations(
      supported ? Locale(chosen.languageCode) : const Locale('en'),
    );
  }

  Future<QuickDownloadOutcome> handle(String text) async {
    try {
      // A cold start reads the saved choices first: the preferred quality
      // and the language come from them.
      await _settings.initialized;
      final l10n = _l10n();
      try {
        return await _downloads.keepingAlive(l10n, () async {
          // The download list holds the process from here on; sent after its
          // own hold, so there is no moment with neither.
          await _channel.releaseKeepAlive();
          return _download(text, l10n);
        });
      } catch (error) {
        // Nobody is looking at a screen to see it went wrong otherwise.
        debugPrint('Quick download failed: $error');
        await _channel.showMessage(
          l10n.quickDownloadUnreadable(l10n.unableToAnalyze),
        );
        return QuickDownloadOutcome.failed;
      }
    } finally {
      // Covers a failure before the download list took over.
      await _channel.releaseKeepAlive();
    }
  }

  Future<QuickDownloadOutcome> _download(
    String text,
    AppLocalizations l10n,
  ) async {
    final urls = UrlHelper.extractUrls(text);
    if (urls.isEmpty) {
      await _channel.showMessage(l10n.quickDownloadNoLink);
      return QuickDownloadOutcome.noLink;
    }

    final read = await _read(urls.first, l10n);
    if (read case _Unread(:final outcome, :final message)) {
      await _channel.showMessage(message);
      return outcome;
    }
    final (metadata, quality) = (read as _Read).selection;
    await _history?.add(metadata);

    final title = metadata.title;
    final qualities = [quality];
    final existing = await _downloads.findExistingDownloads(
      metadata: metadata,
      qualities: qualities,
      l10n: l10n,
    );
    if (existing.isNotEmpty) {
      await _channel.showMessage(l10n.quickDownloadAlreadySaved(title));
      return QuickDownloadOutcome.alreadySaved;
    }
    if (_downloads.isInProgress(
      metadata: metadata,
      qualities: qualities,
      l10n: l10n,
    )) {
      await _channel.showMessage(l10n.quickDownloadAlreadyRunning(title));
      return QuickDownloadOutcome.alreadyRunning;
    }

    final before = _downloads.allTasks.toSet();
    await _downloads.startNewDownloads(
      metadata: metadata,
      qualities: qualities,
      l10n: l10n,
      options: _settings.downloadOptions,
    );
    if (!_downloads.networkAllowsDownloads) {
      // It starts by itself on Wi-Fi; holding the process until then could
      // be hours.
      await _channel.showMessage(l10n.quickDownloadWaitingForWifi(title));
      return QuickDownloadOutcome.waitingForWifi;
    }
    await _channel.showMessage(l10n.quickDownloadStarted(title));

    // A video joined on the device enters the list a moment after starting.
    // Taken by what is new rather than by what is running: a small file can
    // be done already.
    await Future<void>.delayed(Duration.zero);
    final tasks = _downloads.allTasks
        .where((task) => !before.contains(task))
        .toList();
    if (tasks.isEmpty) return QuickDownloadOutcome.started;

    final finished = await _settled(tasks);
    if (!finished) return QuickDownloadOutcome.started;
    if (tasks.any((task) => task.status == DownloadStatus.failed)) {
      await _channel.showMessage(l10n.quickDownloadFailed(title));
      return QuickDownloadOutcome.failed;
    }
    if (tasks.every(
      (task) =>
          task.status == DownloadStatus.completed ||
          task.status == DownloadStatus.handedOff,
    )) {
      await _channel.showMessage(l10n.quickDownloadSaved(title));
      return QuickDownloadOutcome.saved;
    }
    // Paused or cancelled from the notification: nothing to announce.
    return QuickDownloadOutcome.started;
  }

  /// Reads [url] the way the home screen does, into an extractor of its own
  /// so that whatever the home screen shows is left alone.
  Future<_ReadResult> _read(String url, AppLocalizations l10n) async {
    final extractor = VideoExtractorProvider(extractorRegistry: _registry);
    try {
      final preferred = _settings.preferredQuality;
      // Which of a playlist's videos to take is a question for the app.
      if (youtubePlaylistIdFrom(url) != null) {
        return _Unread(
          QuickDownloadOutcome.needsApp,
          l10n.quickDownloadPlaylist,
        );
      }
      if (VideoExtractorProvider.isPlaylistLink(url)) {
        // Such a link may still name a single video, which reads as one.
        final results = await extractor.analyzeUrls(
          [url],
          preferredQuality: preferred,
          l10n: l10n,
        );
        if (results.length != 1) {
          return _Unread(
            QuickDownloadOutcome.needsApp,
            l10n.quickDownloadPlaylist,
          );
        }
        final only = results.single;
        final metadata = only.metadata;
        final quality = only.selectedQuality;
        if (metadata == null || quality == null) {
          return _Unread(
            QuickDownloadOutcome.unreadable,
            l10n.quickDownloadUnreadable(only.error ?? l10n.unableToAnalyze),
          );
        }
        return _Read((metadata, quality));
      }
      final ok = await extractor.analyzeUrl(
        url,
        preferredQuality: preferred,
        l10n: l10n,
      );
      final metadata = extractor.metadata;
      final quality = extractor.selectedQuality;
      if (!ok || metadata == null || quality == null) {
        return _Unread(
          QuickDownloadOutcome.unreadable,
          l10n.quickDownloadUnreadable(
            extractor.errorMessage ?? l10n.unableToAnalyze,
          ),
        );
      }
      return _Read((metadata, quality));
    } finally {
      extractor.dispose();
    }
  }

  /// Completes with true once none of [tasks] is queued or running any more,
  /// or false when [_completionLimit] runs out first.
  Future<bool> _settled(List<DownloadTask> tasks) {
    bool done() => tasks.every((task) => !task.isActive);
    if (done()) return Future.value(true);
    final completer = Completer<bool>();
    void check() {
      if (!completer.isCompleted && done()) completer.complete(true);
    }

    _downloads.addListener(check);
    for (final task in tasks) {
      task.addListener(check);
    }
    final limit = Timer(_completionLimit, () {
      if (!completer.isCompleted) completer.complete(false);
    });
    return completer.future.whenComplete(() {
      limit.cancel();
      _downloads.removeListener(check);
      for (final task in tasks) {
        task.removeListener(check);
      }
    });
  }
}

sealed class _ReadResult {}

class _Read extends _ReadResult {
  _Read(this.selection);

  final (VideoMetadata, VideoQualityOption) selection;
}

class _Unread extends _ReadResult {
  _Unread(this.outcome, this.message);

  final QuickDownloadOutcome outcome;
  final String message;
}
