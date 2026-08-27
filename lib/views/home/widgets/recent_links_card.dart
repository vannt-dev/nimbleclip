import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/platform_style.dart';
import 'package:provider/provider.dart';
import '../../../l10n/l10n.dart';
import '../../../models/analysis_history_entry.dart';
import '../../../providers/analysis_history_provider.dart';

/// The five most recent analyses, each replayable in one tap.
class RecentLinksCard extends StatelessWidget {
  const RecentLinksCard({
    super.key,
    required this.entries,
    required this.onReplay,
  });

  final List<AnalysisHistoryEntry> entries;
  final void Function(String url) onReplay;

  @override
  Widget build(BuildContext context) {
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
                onTap: () => onReplay(entry.originalUrl),
              ),
          ],
        ),
      ),
    );
  }
}
