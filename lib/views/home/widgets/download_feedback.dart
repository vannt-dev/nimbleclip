import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../l10n/l10n.dart';
import '../../../models/download_task.dart';
import '../../../providers/download_provider.dart';

/// The dialogs and notifications the home screen shows around a download.
///
/// Pulled out of `_onStartDownload`, which had grown to ninety-five lines by
/// interleaving three jobs: deciding what to do, doing it, and telling the
/// reader about it. This file owns the third.
class DownloadFeedback {
  const DownloadFeedback._();

  /// Asks whether to download something the reader already has.
  ///
  /// Returns false when dismissed, so the caller can treat "no answer" and
  /// "no" the same way.
  static Future<bool> confirmDuplicate(
    BuildContext context,
    int existingCount,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.duplicateDownloadTitle),
        content: Text(
          dialogContext.l10n.duplicateDownloadMessage(existingCount),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.l10n.downloadAgain),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// Reports that the selection is already downloading.
  static void showAlreadyInProgress(
    BuildContext context, {
    required VoidCallback onViewProgress,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.l10n.downloadAlreadyInProgress),
          action: SnackBarAction(
            label: context.l10n.viewProgress,
            onPressed: onViewProgress,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// Shows a notification that stays up until [tasks] all leave the active
  /// state, then closes itself.
  ///
  /// The lifetime is the fiddly part. The bar outlives the call, so its
  /// listener has to be removed on both exits — the tasks finishing, and the
  /// reader dismissing the bar first — or the provider keeps calling into a
  /// closure whose notification is already gone.
  static void showStarted(
    BuildContext context, {
    required DownloadProvider provider,
    required List<DownloadTask> tasks,
    required String title,
    required VoidCallback onViewProgress,
  }) {
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final notification = messenger.showSnackBar(
      SnackBar(
        content: Text(
          tasks.length == 1
              ? context.l10n.downloadStarted(title, tasks.first.qualityLabel)
              : context.l10n.batchDownloadStarted(tasks.length),
        ),
        action: SnackBarAction(
          label: context.l10n.viewProgress,
          textColor: AppColors.tiktokAccent,
          onPressed: onViewProgress,
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(days: 1),
      ),
    );

    void closeWhenFinished() {
      if (tasks.any((task) => task.isActive)) return;
      provider.removeListener(closeWhenFinished);
      notification.close();
    }

    provider.addListener(closeWhenFinished);
    unawaited(
      notification.closed.then((_) {
        provider.removeListener(closeWhenFinished);
      }),
    );
    // Everything may already be done by the time the bar goes up.
    closeWhenFinished();
  }

  /// Reports the outcome of a batch, which reports a count rather than a title.
  static void showBatchStarted(
    BuildContext context, {
    required int queued,
    required VoidCallback onViewProgress,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.batchDownloadStarted(queued)),
        action: SnackBarAction(
          label: context.l10n.viewProgress,
          onPressed: onViewProgress,
        ),
      ),
    );
  }
}
