import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../l10n/l10n.dart';

/// Switches the option list below between visual media and audio.
///
/// Renders nothing unless the post has audio *and* something visual — with
/// only one kind there is nothing to switch between, and the list speaks for
/// itself.
class ResultMediaTabs extends StatelessWidget {
  const ResultMediaTabs({
    super.key,
    required this.selectedTab,
    required this.videoCount,
    required this.imageCount,
    required this.audioCount,
    required this.onVisualSelected,
    required this.onAudioSelected,
  });

  /// 0 = visual media, 1 = audio.
  final int selectedTab;

  final int videoCount;
  final int imageCount;
  final int audioCount;

  final VoidCallback onVisualSelected;
  final VoidCallback onAudioSelected;

  @override
  Widget build(BuildContext context) {
    final hasVisual = videoCount > 0 || imageCount > 0;
    if (audioCount == 0 || !hasVisual) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Videos win the label when a post carries both; a mixed post is shown
    // through the picker rather than this row.
    final visualLabel = videoCount > 0
        ? context.l10n.videoOptions(videoCount)
        : context.l10n.imageOptions(imageCount);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkCardElevated
            : AppColors.lightCardElevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Tab(
              label: visualLabel,
              isSelected: selectedTab == 0,
              isDark: isDark,
              onTap: onVisualSelected,
            ),
          ),
          Expanded(
            child: _Tab(
              label: context.l10n.audioOptions(audioCount),
              isSelected: selectedTab == 1,
              isDark: isDark,
              onTap: onAudioSelected,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected
                ? Colors.white
                : (isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary),
          ),
        ),
      ),
    );
  }
}
