import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/url_helper.dart';
import '../../providers/download_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/video_extractor_provider.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkClipboardAutoPaste();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _urlController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkClipboardAutoPaste();
    }
  }

  Future<void> _checkClipboardAutoPaste() async {
    final settings = context.read<SettingsProvider>();
    if (!settings.autoPasteClipboard) return;

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
                  const Expanded(
                    child: Text('Phát hiện liên kết video trong Clipboard!'),
                  ),
                ],
              ),
              action: SnackBarAction(
                label: 'Dán & Tải',
                textColor: AppColors.tiktokAccent,
                onPressed: () {
                  _urlController.text = clean;
                  _onAnalyze();
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

  void _onAnalyze() {
    final text = _urlController.text.trim();
    if (text.isNotEmpty) {
      FocusScope.of(context).unfocus();
      final preferred = context.read<SettingsProvider>().preferredQuality;
      context
          .read<VideoExtractorProvider>()
          .analyzeUrl(text, preferredQuality: preferred);
    }
  }

  void _onClear() {
    _urlController.clear();
    context.read<VideoExtractorProvider>().clear();
    setState(() {});
  }

  void _onStartDownload() {
    final extractor = context.read<VideoExtractorProvider>();
    final settings = context.read<SettingsProvider>();
    final meta = extractor.metadata;
    final quality = extractor.selectedQuality;

    if (meta != null && quality != null) {
      context.read<DownloadProvider>().startNewDownload(
            metadata: meta,
            quality: quality,
            autoSaveToGallery: settings.autoSaveGallery,
          );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đang tải: ${meta.title} (${quality.quality})'),
          action: SnackBarAction(
            label: 'Xem tiến trình',
            textColor: AppColors.tiktokAccent,
            onPressed: widget.onNavigateDownloads,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _onPreviewVideo() {
    final extractor = context.read<VideoExtractorProvider>();
    final meta = extractor.metadata;
    final quality = extractor.selectedQuality;

    if (meta != null && quality != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            title: meta.title,
            videoUrl: quality.downloadUrl,
            onDownload: _onStartDownload,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final extractor = context.watch<VideoExtractorProvider>();

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            if (_urlController.text.isNotEmpty) {
              _onAnalyze();
            }
          },
          child: SingleChildScrollView(
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
                          AppConstants.appTagline,
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
                          'Hỗ trợ tải video từ ${platform.displayName} chất lượng cao!',
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
                  isAnalyzing: extractor.isAnalyzing,
                  onAnalyze: _onAnalyze,
                  onClear: _onClear,
                  onChanged: (val) => setState(() {}),
                ),
                const SizedBox(height: 20),

                // 4. Extraction Error Message
                if (extractor.errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.error.withAlpha(25),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.error.withAlpha(80),
                      ),
                    ),
                    child: Row(
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
                    onPreview: _onPreviewVideo,
                  ),
                  const SizedBox(height: 24),
                ],

                // 6. How-to Guide Cards (Shown when no result)
                if (extractor.metadata == null && !extractor.isAnalyzing) ...[
                  _buildHowToGuide(isDark),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHowToGuide(bool isDark) {
    final steps = [
      {
        'num': '1',
        'title': 'Sao chép liên kết video',
        'desc': 'Mở YouTube, TikTok, Facebook hoặc X và bấm "Sao chép liên kết".',
        'icon': Icons.copy_rounded,
      },
      {
        'num': '2',
        'title': 'Dán liên kết vào ứng dụng',
        'desc': 'Bấm nút Dán hoặc nhập URL vào thanh tìm kiếm ở trên.',
        'icon': Icons.paste_rounded,
      },
      {
        'num': '3',
        'title': 'Chọn chất lượng & Tải về',
        'desc': 'Xem trước video và tải về định dạng HD 1080p hoặc Âm thanh MP3.',
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
                'Hướng dẫn sử dụng nhanh',
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
