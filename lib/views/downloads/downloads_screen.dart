import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../l10n/l10n.dart';
import '../../models/download_task.dart';
import '../../providers/download_provider.dart';
import '../player/video_player_screen.dart';
import 'widgets/active_download_card.dart';
import 'widgets/completed_download_card.dart';

class DownloadsScreen extends StatefulWidget {
  final VoidCallback onNavigateHome;

  const DownloadsScreen({super.key, required this.onNavigateHome});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _playVideo(BuildContext context, DownloadTask task) {
    if (task.filePath == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          title: task.title,
          localFilePath: task.filePath,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, DownloadTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.confirmDeleteTitle),
        content: Text(context.l10n.confirmDeleteMessage(task.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      context.read<DownloadProvider>().deleteTask(task.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.videoDeleted),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Card used for anything still in flight, including paused tasks — they are
  /// not finished, so they belong with the running downloads rather than in the
  /// completed list.
  Widget _activeCard(BuildContext context, DownloadTask task) {
    final provider = context.read<DownloadProvider>();
    return ActiveDownloadCard(
      task: task,
      onCancel: () => provider.cancelTask(task.id),
      onPause: kIsWeb ? null : () => provider.pauseTask(task.id),
      onResume: kIsWeb
          ? null
          : () => provider.resumeTask(task, l10n: context.l10n),
    );
  }

  Future<void> _confirmClearFinished(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.clearFinishedTitle),
        content: Text(context.l10n.clearFinishedMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await context.read<DownloadProvider>().clearFinished();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final downloadProv = context.watch<DownloadProvider>();

    final all = downloadProv.allTasks;
    final active = [...downloadProv.activeTasks, ...downloadProv.pausedTasks];
    final completed = downloadProv.completedTasks;
    final hasFinished = all.any((t) => t.isDone);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.downloadsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.playlist_remove_rounded),
            tooltip: context.l10n.clearFinished,
            onPressed:
                hasFinished ? () => _confirmClearFinished(context) : null,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelColor: isDark ? Colors.white : AppColors.primary,
          unselectedLabelColor: isDark
              ? AppColors.darkTextSecondary
              : AppColors.lightTextSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: [
            Tab(text: context.l10n.tabAll(all.length)),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(context.l10n.tabDownloading),
                  if (active.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${active.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(text: context.l10n.tabDownloaded(completed.length)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTaskList(context, all, isAll: true),
          _buildActiveList(context, active),
          _buildCompletedList(context, completed),
        ],
      ),
    );
  }

  Widget _buildActiveList(BuildContext context, List<DownloadTask> tasks) {
    if (tasks.isEmpty) {
      return _buildEmptyState(
        icon: Icons.cloud_download_outlined,
        title: context.l10n.noActiveDownloads,
        subtitle: context.l10n.noActiveDownloadsDescription,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      itemBuilder: (context, index) => _activeCard(context, tasks[index]),
    );
  }

  Widget _buildCompletedList(BuildContext context, List<DownloadTask> tasks) {
    if (tasks.isEmpty) {
      return _buildEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: context.l10n.noCompletedDownloads,
        subtitle: context.l10n.noCompletedDownloadsDescription,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return CompletedDownloadCard(
          task: task,
          onPlay: () => _playVideo(context, task),
          onSaveGallery: () async {
            final saved = await context
                .read<DownloadProvider>()
                .saveToGalleryManually(task);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    saved
                        ? context.l10n.savedToGallery
                        : context.l10n.gallerySaveFailed,
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          onShare: () => context.read<DownloadProvider>().shareFile(
                task,
                context.l10n.shareFromNimbleClip(task.title),
              ),
          onOpenExternal: () =>
              context.read<DownloadProvider>().openFile(task),
          onDelete: () => _confirmDelete(context, task),
          onRetry: () => context.read<DownloadProvider>().retryTask(
                task,
                l10n: context.l10n,
              ),
        );
      },
    );
  }

  Widget _buildTaskList(BuildContext context, List<DownloadTask> tasks,
      {bool isAll = false}) {
    if (tasks.isEmpty) {
      return _buildEmptyState(
        icon: Icons.video_library_outlined,
        title: context.l10n.emptyDownloadList,
        subtitle: context.l10n.emptyDownloadListDescription,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        if (task.isActive || task.status == DownloadStatus.paused) {
          return _activeCard(context, task);
        } else {
          return CompletedDownloadCard(
            task: task,
            onPlay: () => _playVideo(context, task),
            onSaveGallery: () async {
              final saved = await context
                  .read<DownloadProvider>()
                  .saveToGalleryManually(task);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      saved
                          ? context.l10n.savedToGallery
                          : context.l10n.gallerySaveFailedShort,
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            onShare: () => context.read<DownloadProvider>().shareFile(
                  task,
                  context.l10n.shareFromNimbleClip(task.title),
                ),
            onOpenExternal: () =>
                context.read<DownloadProvider>().openFile(task),
            onDelete: () => _confirmDelete(context, task),
            onRetry: () => context.read<DownloadProvider>().retryTask(
                  task,
                  l10n: context.l10n,
                ),
          );
        }
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkCardElevated
                    : AppColors.lightCardElevated,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 48,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: widget.onNavigateHome,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(context.l10n.newDownload),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
