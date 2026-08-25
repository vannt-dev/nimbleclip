import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/url_helper.dart';
import '../../l10n/l10n.dart';
import '../../models/video_metadata.dart';
import '../../models/analysis_history_entry.dart';
import '../../providers/download_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/video_extractor_provider.dart';
import '../../providers/analysis_history_provider.dart';
import '../../providers/shared_intent_provider.dart';
import '../player/video_player_screen.dart';
import 'widgets/platform_badges.dart';
import 'widgets/url_input_card.dart';
import 'widgets/video_result_card.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onNavigateDownloads;

  const HomeScreen({super.key, required this.onNavigateDownloads});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final TextEditingController _urlController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _urlFocusNode = FocusNode();
  bool _handlingSharedIntent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkClipboardAutoPaste());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _urlController.dispose();
    _scrollController.dispose();
    _urlFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkClipboardAutoPaste());
    }
  }

  Future<void> _checkClipboardAutoPaste() async {
    final settings = context.read<SettingsProvider>();
    if (!settings.autoPasteClipboard) return;
    if (context.read<VideoExtractorProvider>().hasResult) return;

    try {
      final data = await Clipboard.getData('text/plain');
      final text = data?.text ?? '';
      final clean = UrlHelper.extractCleanUrl(text);

      if (UrlHelper.isValidVideoUrl(clean) && clean != _urlController.text) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.link_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(context.l10n.clipboardVideoDetected)),
                ],
              ),
              action: SnackBarAction(
                label: context.l10n.pasteAndDownload,
                textColor: AppColors.tiktokAccent,
                onPressed: () {
                  _urlController.text = clean;
                  unawaited(_onAnalyze());
                },
              ),
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (_) {
      // Ignore clipboard permission errors on browser
    }
  }

  Future<void> _onAnalyze() async {
    final text = _urlController.text.trim();
    final urls = UrlHelper.extractUrls(text);
    if (urls.isNotEmpty) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      FocusScope.of(context).unfocus();
      final preferred = context.read<SettingsProvider>().preferredQuality;
      final extractor = context.read<VideoExtractorProvider>();
      if (urls.length > VideoExtractorProvider.maximumBatchUrls) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.batchLimitReached(
                VideoExtractorProvider.maximumBatchUrls,
              ),
            ),
          ),
        );
      }
      if (urls.length == 1) {
        final ok = await extractor.analyzeUrl(
          urls.single,
          preferredQuality: preferred,
          l10n: context.l10n,
        );
        if (ok && mounted && extractor.metadata != null) {
          await context.read<AnalysisHistoryProvider>().add(
            extractor.metadata!,
          );
        }
      } else {
        final results = await extractor.analyzeUrls(
          urls,
          preferredQuality: preferred,
          l10n: context.l10n,
        );
        if (!mounted) return;
        final history = context.read<AnalysisHistoryProvider>();
        for (final result in results) {
          if (result.metadata != null) await history.add(result.metadata!);
        }
      }
    }
  }

  void _consumeSharedIntent() {
    if (_handlingSharedIntent) return;
    final shared = context.read<SharedIntentProvider>().consume();
    if (shared == null) return;
    _handlingSharedIntent = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _urlController.text = UrlHelper.extractUrls(shared).join('\n');
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      await _onAnalyze();
      _handlingSharedIntent = false;
    });
  }

  void _onClear() {
    _urlController.clear();
    context.read<VideoExtractorProvider>().clear();
  }

  Future<void> _copyDiagnostics(VideoExtractorProvider extractor) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final duration = extractor.lastAnalysisDuration;
    final analyzedAt = extractor.lastAnalyzedAt;
    await Clipboard.setData(
      ClipboardData(
        text: [
          'Code: ${extractor.diagnosticCode}',
          'URL: ${extractor.currentUrl}',
          'Platform: ${UrlHelper.detectPlatform(extractor.currentUrl).name}',
          'Strategies: ${extractor.attemptedStrategies.join(', ')}',
          if (duration != null) 'Duration: ${duration.inMilliseconds}ms',
          if (analyzedAt != null)
            'Analyzed at: ${analyzedAt.toIso8601String()}',
          'App: ${packageInfo.version}+${packageInfo.buildNumber}',
        ].join('\n'),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.diagnosticsCopied)));
  }

  Future<void> _startNewDownload() async {
    _onClear();

    // Wait for the result card to leave the tree before calculating the new
    // scroll extent, then return to the input and open the keyboard.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
    if (mounted) _urlFocusNode.requestFocus();
  }

  Future<void> _onStartDownload([List<VideoQualityOption>? qualities]) async {
    final extractor = context.read<VideoExtractorProvider>();
    final settings = context.read<SettingsProvider>();
    final meta = extractor.metadata;
    final selected = qualities ?? [extractor.selectedQuality].nonNulls.toList();

    if (meta != null && selected.isNotEmpty) {
      final provider = context.read<DownloadProvider>();
      final existing = await provider.findExistingDownloads(
        metadata: meta,
        qualities: selected,
      );
      if (!mounted) return;
      if (existing.isNotEmpty) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(context.l10n.duplicateDownloadTitle),
            content: Text(
              context.l10n.duplicateDownloadMessage(existing.length),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(context.l10n.downloadAgain),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }

      final tasks = await provider.startNewDownloads(
        metadata: meta,
        qualities: selected,
        l10n: context.l10n,
        options: settings.downloadOptions,
      );
      if (!mounted) return;
      if (tasks.isEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(context.l10n.downloadAlreadyInProgress),
              action: SnackBarAction(
                label: context.l10n.viewProgress,
                onPressed: widget.onNavigateDownloads,
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        return;
      }

      final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
      final notification = messenger.showSnackBar(
        SnackBar(
          content: Text(
            tasks.length == 1
                ? context.l10n.downloadStarted(
                    meta.title,
                    tasks.first.qualityLabel,
                  )
                : context.l10n.batchDownloadStarted(tasks.length),
          ),
          action: SnackBarAction(
            label: context.l10n.viewProgress,
            textColor: AppColors.tiktokAccent,
            onPressed: widget.onNavigateDownloads,
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(days: 1),
        ),
      );
      void closeWhenFinished() {
        final finished = tasks.every((task) => !task.isActive);
        if (!finished) return;
        provider.removeListener(closeWhenFinished);
        notification.close();
      }

      provider.addListener(closeWhenFinished);
      unawaited(
        notification.closed.then((_) {
          provider.removeListener(closeWhenFinished);
        }),
      );
      closeWhenFinished();
    }
  }

  Future<void> _onStartBatchDownload() async {
    final results = context.read<VideoExtractorProvider>().batchResults.where(
      (result) => result.metadata != null && result.selectedQuality != null,
    );
    final downloads = context.read<DownloadProvider>();
    final settings = context.read<SettingsProvider>();
    final l10n = context.l10n;
    var queued = 0;
    for (final result in results) {
      final metadata = result.metadata!;
      final quality = result.selectedQuality!;
      final existing = await downloads.findExistingDownloads(
        metadata: metadata,
        qualities: [quality],
      );
      if (existing.isNotEmpty) continue;
      final tasks = await downloads.startNewDownloads(
        metadata: metadata,
        qualities: [quality],
        l10n: l10n,
        options: settings.downloadOptions,
      );
      queued += tasks.length;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.batchDownloadStarted(queued)),
        action: SnackBarAction(
          label: context.l10n.viewProgress,
          onPressed: widget.onNavigateDownloads,
        ),
      ),
    );
  }

  Future<void> _retryBatchResult(String url) async {
    final extractor = context.read<VideoExtractorProvider>();
    await extractor.retryBatchResult(
      url,
      preferredQuality: context.read<SettingsProvider>().preferredQuality,
      l10n: context.l10n,
    );
    if (!mounted) return;
    final result = extractor.batchResults
        .where((entry) => entry.url == url)
        .firstOrNull;
    if (result?.metadata != null) {
      await context.read<AnalysisHistoryProvider>().add(result!.metadata!);
    }
  }

  void _onPreviewMedia() {
    final extractor = context.read<VideoExtractorProvider>();
    final meta = extractor.metadata;
    final quality = extractor.selectedQuality;

    if (meta != null && quality != null) {
      if (quality.isImage) {
        unawaited(
          showDialog<void>(
            context: context,
            builder: (dialogContext) => Dialog(
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: CachedNetworkImage(
                      imageUrl: quality.downloadUrl,
                      fit: BoxFit.contain,
                      placeholder: (_, _) => const SizedBox(
                        height: 320,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (_, _, _) => const SizedBox(
                        height: 240,
                        child: Center(child: Icon(Icons.broken_image_outlined)),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton.filledTonal(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        return;
      }
      unawaited(
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(
              title: meta.title,
              videoUrl: quality.downloadUrl,
              onDownload: _onStartDownload,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final extractor = context.watch<VideoExtractorProvider>();
    final sharedText = context.watch<SharedIntentProvider>().pendingText;
    final history = context.watch<AnalysisHistoryProvider>().entries;
    if (sharedText != null) _consumeSharedIntent();

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _startNewDownload,
          child: SingleChildScrollView(
            key: const ValueKey('home-scroll-view'),
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Header & App Branding
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.accent],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.bolt_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppConstants.appName,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          context.l10n.appTagline,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 2. Supported Platforms Pills Bar
                PlatformBadges(
                  onPlatformTap: (platform) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          context.l10n.platformSupported(platform.displayName),
                        ),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),

                // 3. URL Input Card
                UrlInputCard(
                  controller: _urlController,
                  focusNode: _urlFocusNode,
                  isAnalyzing: extractor.isAnalyzing,
                  onAnalyze: _onAnalyze,
                  onClear: _onClear,
                ),
                const SizedBox(height: 20),

                // 4. Extraction Error Message
                if (extractor.errorMessage != null) ...[
                  Semantics(
                    liveRegion: true,
                    container: true,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.error.withAlpha(25),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.error.withAlpha(80),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: AppColors.error,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  extractor.errorMessage!,
                                  style: const TextStyle(
                                    color: AppColors.error,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (extractor.diagnosticCode != null) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () =>
                                    unawaited(_copyDiagnostics(extractor)),
                                icon: const Icon(Icons.copy_rounded, size: 16),
                                label: Text(context.l10n.copyDiagnostics),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // 5. Video Result Card (if metadata extracted)
                if (extractor.metadata != null) ...[
                  VideoResultCard(
                    metadata: extractor.metadata!,
                    selectedQuality: extractor.selectedQuality,
                    onQualitySelected: extractor.selectQuality,
                    onDownload: _onStartDownload,
                    onPreview: _onPreviewMedia,
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    key: const ValueKey('home-new-download'),
                    onPressed: () => unawaited(_startNewDownload()),
                    icon: const Icon(Icons.add_link_rounded),
                    label: Text(context.l10n.newDownload),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                if (extractor.batchResults.isNotEmpty) ...[
                  _buildBatchResults(extractor.batchResults),
                  const SizedBox(height: 20),
                ],

                // 6. How-to Guide Cards (Shown when no result)
                if (extractor.metadata == null && !extractor.isAnalyzing) ...[
                  _buildHowToGuide(isDark),
                  const SizedBox(height: 20),
                ],
                if (history.isNotEmpty) ...[
                  _buildRecentLinks(history),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBatchResults(List<BatchAnalysisResult> results) {
    final successes = results.where((result) => result.isSuccess).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.batchResults(results.length),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (context.watch<VideoExtractorProvider>().isAnalyzing)
              Semantics(
                liveRegion: true,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: context
                        .read<VideoExtractorProvider>()
                        .cancelBatchAnalysis,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(context.l10n.cancel),
                  ),
                ),
              ),
            for (final result in results)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  result.isSuccess ? Icons.check_circle : Icons.error_outline,
                  color: result.isSuccess ? AppColors.success : AppColors.error,
                ),
                title: Text(
                  result.metadata?.title ?? result.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: result.error != null
                    ? Text(
                        result.error!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                    : result.metadata!.qualities.length > 1
                    ? DropdownButton<VideoQualityOption>(
                        value: result.selectedQuality,
                        isExpanded: true,
                        items: [
                          for (final quality in result.metadata!.qualities)
                            DropdownMenuItem(
                              value: quality,
                              child: Text(
                                quality.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (quality) {
                          if (quality != null) {
                            context
                                .read<VideoExtractorProvider>()
                                .selectBatchQuality(result.url, quality);
                          }
                        },
                      )
                    : Text(result.selectedQuality?.label ?? ''),
                trailing: result.isSuccess
                    ? null
                    : IconButton(
                        tooltip: context.l10n.retry,
                        onPressed: () =>
                            unawaited(_retryBatchResult(result.url)),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
              ),
            FilledButton.icon(
              onPressed: successes == 0
                  ? null
                  : () => unawaited(_onStartBatchDownload()),
              icon: const Icon(Icons.playlist_add_rounded),
              label: Text(context.l10n.queueAll(successes)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentLinks(List<AnalysisHistoryEntry> entries) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.recentLinks,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => unawaited(
                    context.read<AnalysisHistoryProvider>().clear(),
                  ),
                  child: Text(context.l10n.clear),
                ),
              ],
            ),
            for (final entry in entries.take(5))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(entry.platform.icon),
                title: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  entry.originalUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.replay_rounded),
                onTap: () {
                  _urlController.text = entry.originalUrl;
                  unawaited(_onAnalyze());
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHowToGuide(bool isDark) {
    final l10n = context.l10n;
    final steps = [
      {
        'num': '1',
        'title': l10n.guideCopyTitle,
        'desc': l10n.guideCopyDescription,
        'icon': Icons.copy_rounded,
      },
      {
        'num': '2',
        'title': l10n.guidePasteTitle,
        'desc': l10n.guidePasteDescription,
        'icon': Icons.paste_rounded,
      },
      {
        'num': '3',
        'title': l10n.guideDownloadTitle,
        'desc': l10n.guideDownloadDescription,
        'icon': Icons.file_download_outlined,
      },
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline_rounded,
                color: AppColors.warning,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.quickGuide,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...steps.map((s) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      s['num'] as String,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s['title'] as String,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s['desc'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
