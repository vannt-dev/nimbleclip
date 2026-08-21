import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../l10n/l10n.dart';
import '../../models/video_metadata.dart';

/// A lazy, full-screen image chooser for carousel posts.
///
/// Keeping the grid outside the home page avoids eagerly decoding every image
/// inside its parent scroll view. Only visible thumbnails are built and cached.
class ImagePickerScreen extends StatefulWidget {
  const ImagePickerScreen({
    super.key,
    required this.options,
    required this.initiallySelectedIds,
  });

  final List<VideoQualityOption> options;
  final Set<String> initiallySelectedIds;

  @override
  State<ImagePickerScreen> createState() => _ImagePickerScreenState();
}

class _ImagePickerScreenState extends State<ImagePickerScreen> {
  late final Set<String> _selectedIds = {...widget.initiallySelectedIds};

  void _toggle(VideoQualityOption option) {
    setState(() {
      if (!_selectedIds.add(option.id)) _selectedIds.remove(option.id);
    });
  }

  void _toggleAll() {
    setState(() {
      if (_selectedIds.length == widget.options.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(widget.options.map((option) => option.id));
      }
    });
  }

  void _preview(VideoQualityOption option) {
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
                  imageUrl: option.downloadUrl,
                  httpHeaders: option.headers,
                  fit: BoxFit.contain,
                  placeholder: (_, _) => const SizedBox(
                    height: 360,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (_, _, _) => const SizedBox(
                    height: 280,
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
  }

  @override
  Widget build(BuildContext context) {
    final allSelected = _selectedIds.length == widget.options.length;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900
        ? 5
        : width >= 600
        ? 4
        : 3;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.selectImages),
        actions: [
          TextButton(
            onPressed: _toggleAll,
            child: Text(
              allSelected ? context.l10n.deselectAll : context.l10n.selectAll,
            ),
          ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.78,
        ),
        itemCount: widget.options.length,
        itemBuilder: (context, index) {
          final option = widget.options[index];
          final selected = _selectedIds.contains(option.id);
          return Semantics(
            label: option.label,
            selected: selected,
            button: true,
            child: Material(
              clipBehavior: Clip.antiAlias,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => _toggle(option),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: option.thumbnailUrl ?? option.downloadUrl,
                      httpHeaders: option.headers,
                      fit: BoxFit.cover,
                      memCacheWidth: 360,
                      placeholder: (_, _) => const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      errorWidget: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : Colors.transparent,
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        color: selected ? AppColors.primary : Colors.white,
                        shadows: const [Shadow(blurRadius: 5)],
                      ),
                    ),
                    Positioned(
                      top: 2,
                      left: 2,
                      child: IconButton(
                        tooltip: context.l10n.preview,
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _preview(option),
                        icon: const Icon(Icons.zoom_in_rounded, size: 18),
                      ),
                    ),
                    Positioned(
                      left: 6,
                      right: 6,
                      bottom: 6,
                      child: Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          shadows: [Shadow(blurRadius: 5)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: FilledButton.icon(
          onPressed: () => Navigator.pop(context, _selectedIds),
          icon: const Icon(Icons.check_rounded),
          label: Text('${context.l10n.selectImages} (${_selectedIds.length})'),
        ),
      ),
    );
  }
}
