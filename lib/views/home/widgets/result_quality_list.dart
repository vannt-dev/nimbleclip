import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/l10n.dart';
import '../../../models/video_metadata.dart';

/// The download options for the active tab, plus the image-selection controls
/// for a post that carries a gallery.
///
/// Selection state stays in `VideoResultCard`; this renders it and reports
/// taps back.
class ResultQualityList extends StatelessWidget {
  const ResultQualityList({
    super.key,
    required this.options,
    required this.selectedQualityId,
    required this.onQualitySelected,
    required this.imageOptions,
    required this.selectedImageIds,
    required this.showImageSelection,
    required this.onToggleAllImages,
    required this.onOpenPicker,
  });

  /// Options for the tab currently in front — video or audio, never images.
  final List<VideoQualityOption> options;

  final String? selectedQualityId;
  final ValueChanged<VideoQualityOption> onQualitySelected;

  final List<VideoQualityOption> imageOptions;
  final Set<String> selectedImageIds;

  /// Images are offered alongside the visual tab only, never under audio.
  final bool showImageSelection;

  final VoidCallback onToggleAllImages;
  final VoidCallback onOpenPicker;

  @override
  Widget build(BuildContext context) {
    final allImagesSelected = selectedImageIds.length == imageOptions.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (options.isNotEmpty) ...[
          Text(
            context.l10n.selectDownloadQuality,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _QualityRow(
                option: option,
                isSelected: selectedQualityId == option.id,
                onTap: () => onQualitySelected(option),
              ),
            ),
        ],
        if (showImageSelection) ...[
          if (options.isNotEmpty) const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.imageOptions(imageOptions.length),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: onToggleAllImages,
                child: Text(
                  allImagesSelected
                      ? context.l10n.deselectAll
                      : context.l10n.selectAll,
                ),
              ),
            ],
          ),
          OutlinedButton.icon(
            onPressed: onOpenPicker,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(
              '${context.l10n.selectImages} '
              '(${selectedImageIds.length}/${imageOptions.length})',
            ),
          ),
        ],
      ],
    );
  }
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final VideoQualityOption option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sizeBytes = option.sizeBytes;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withAlpha(isDark ? 40 : 25)
              : (isDark
                    ? AppColors.darkCardElevated.withAlpha(120)
                    : AppColors.lightCardElevated),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 18,
              color: isSelected
                  ? AppColors.primary
                  : (isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                option.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? (isDark ? Colors.white : AppColors.primaryDark)
                      : (isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary),
                ),
              ),
            ),
            if (sizeBytes != null && sizeBytes > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  Formatters.formatBytes(sizeBytes),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
