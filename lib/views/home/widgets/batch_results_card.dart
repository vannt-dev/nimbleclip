import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/quality_descriptor_text.dart';
import '../../../models/video_metadata.dart';
import '../../../providers/video_extractor_provider.dart';

/// Outcome of a multi-link analysis: one row per link, plus the queue-all
/// action for the ones that resolved.
class BatchResultsCard extends StatelessWidget {
  const BatchResultsCard({
    super.key,
    required this.results,
    required this.onRetry,
    required this.onQueueAll,
  });

  final List<BatchAnalysisResult> results;
  final void Function(String url) onRetry;
  final VoidCallback onQueueAll;

  @override
  Widget build(BuildContext context) {
    final successes = results.where((result) => result.isSuccess).length;
    final isAnalyzing = context.select<VideoExtractorProvider, bool>(
      (provider) => provider.isAnalyzing,
    );

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
            if (isAnalyzing)
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
              _BatchResultTile(result: result, onRetry: onRetry),
            FilledButton.icon(
              onPressed: successes == 0 ? null : onQueueAll,
              icon: const Icon(Icons.playlist_add_rounded),
              label: Text(context.l10n.queueAll(successes)),
            ),
          ],
        ),
      ),
    );
  }
}

class _BatchResultTile extends StatelessWidget {
  const _BatchResultTile({required this.result, required this.onRetry});

  final BatchAnalysisResult result;
  final void Function(String url) onRetry;

  Widget _subtitle(BuildContext context) {
    final error = result.error;
    if (error != null) {
      return Text(error, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    final qualities = result.metadata!.qualities;
    final selected = result.selectedQuality;
    if (qualities.length <= 1) {
      return Text(
        selected == null ? '' : describeQuality(selected.label, context.l10n),
      );
    }
    return DropdownButton<VideoQualityOption>(
      value: result.selectedQuality,
      isExpanded: true,
      items: [
        for (final quality in qualities)
          DropdownMenuItem(
            value: quality,
            child: Text(
              describeQuality(quality.label, context.l10n),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (quality) {
        if (quality == null) return;
        context.read<VideoExtractorProvider>().selectBatchQuality(
          result.url,
          quality,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
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
      subtitle: _subtitle(context),
      trailing: result.isSuccess
          ? null
          : IconButton(
              tooltip: context.l10n.retry,
              onPressed: () => onRetry(result.url),
              icon: const Icon(Icons.refresh_rounded),
            ),
    );
  }
}
