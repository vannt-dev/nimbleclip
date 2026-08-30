import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';

import '../../../core/theme/platform_style.dart';
import '../../../l10n/l10n.dart';
import '../../../models/analysis_history_entry.dart';
import '../../../providers/analysis_history_provider.dart';

/// The five most recent analyses, each replayable in one tap.
///
/// Kept closed by default. Laid out flat the five entries stood between the
/// link field and the result, which is the wrong thing to give that much of
/// the page to: the list is for going back to something, not for reading on
/// the way forward.
class RecentLinksCard extends StatelessWidget {
  const RecentLinksCard({
    super.key,
    required this.entries,
    required this.onReplay,
  });

  final List<AnalysisHistoryEntry> entries;
  final void Function(String url) onReplay;

  static const _visibleCount = 5;

  @override
  Widget build(BuildContext context) {
    final visible = entries.take(_visibleCount).toList();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        // The count is what makes a closed section worth having: it says
        // whether there is anything in there before it is opened.
        title: Text(
          '${context.l10n.recentLinks} (${visible.length})',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          for (final entry in visible)
            _RecentLinkTile(entry: entry, onReplay: onReplay),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              // Inside the section on purpose: clearing a list nobody can see
              // is not something to offer in one stray tap.
              child: TextButton(
                onPressed: () =>
                    unawaited(context.read<AnalysisHistoryProvider>().clear()),
                child: Text(context.l10n.clear),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentLinkTile extends StatelessWidget {
  const _RecentLinkTile({required this.entry, required this.onReplay});

  final AnalysisHistoryEntry entry;
  final void Function(String url) onReplay;

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final copied = context.l10n.linkCopied;
    await Clipboard.setData(ClipboardData(text: entry.originalUrl));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(copied), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(entry.platform.icon),
      title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        entry.originalUrl,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      // Copying is its own button rather than a second meaning for the tap:
      // wanting the link back and wanting the analysis run again are different
      // errands, and one of them costs a network round trip.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: context.l10n.copyLink,
            onPressed: () => unawaited(_copy(context)),
          ),
          const Icon(Icons.replay_rounded),
        ],
      ),
      onTap: () => onReplay(entry.originalUrl),
    );
  }
}
