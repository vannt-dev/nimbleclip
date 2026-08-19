import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/url_helper.dart';
import '../../../l10n/l10n.dart';
import '../../../models/video_platform.dart';

class UrlInputCard extends StatelessWidget {
  final TextEditingController controller;
  final bool isAnalyzing;
  final VoidCallback onAnalyze;
  final VoidCallback onClear;
  final Function(String url) onChanged;

  const UrlInputCard({
    super.key,
    required this.controller,
    required this.isAnalyzing,
    required this.onAnalyze,
    required this.onClear,
    required this.onChanged,
  });

  Future<void> _pasteFromClipboard(BuildContext context) async {
    try {
      final data = await Clipboard.getData('text/plain');
      if (data?.text != null && data!.text!.isNotEmpty) {
        final clean = UrlHelper.extractCleanUrl(data.text!);
        controller.text = clean;
        onChanged(clean);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.clipboardPasted),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (_) {
      // Ignore clipboard read errors
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final detectedPlatform = UrlHelper.detectPlatform(controller.text);
    final hasText = controller.text.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withAlpha(50)
                : AppColors.primary.withAlpha(15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.link_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                context.l10n.pasteVideoLink,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
              const Spacer(),
              if (hasText && detectedPlatform != VideoPlatform.generic)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: detectedPlatform.brandColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        detectedPlatform.icon,
                        size: 14,
                        color: detectedPlatform.brandColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        detectedPlatform.displayName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: detectedPlatform.brandColor,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => onAnalyze(),
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'https://youtube.com/..., tiktok.com/..., fb.watch/...',
              hintStyle: TextStyle(
                color: isDark
                    ? AppColors.darkTextSecondary.withAlpha(120)
                    : AppColors.lightTextSecondary.withAlpha(120),
                fontSize: 13,
              ),
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasText)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: onClear,
                      tooltip: context.l10n.clear,
                    ),
                  IconButton(
                    icon: const Icon(Icons.content_paste_rounded, size: 18),
                    onPressed: () => _pasteFromClipboard(context),
                    tooltip: context.l10n.paste,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: isAnalyzing ? null : onAnalyze,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: isAnalyzing
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.download_rounded, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.analyzeAndDownload,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
