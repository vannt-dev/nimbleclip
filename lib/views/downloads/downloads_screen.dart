import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
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
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa "${task.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      context.read<DownloadProvider>().deleteTask(task.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã xóa video.'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final downloadProv = context.watch<DownloadProvider>();

    final all = downloadProv.allTasks;
    final active = downloadProv.activeTasks;
    final completed = downloadProv.completedTasks;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý tải về'),
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
            Tab(text: 'Tất cả (${all.length})'),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Đang tải'),
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
            Tab(text: 'Đã tải (${completed.length})'),
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
        title: 'Không có tiến trình tải nào',
        subtitle: 'Các video đang tải về sẽ xuất hiện ở đây.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return ActiveDownloadCard(
          task: task,
          onCancel: () => context.read<DownloadProvider>().cancelTask(task.id),
        );
      },
    );
  }

  Widget _buildCompletedList(BuildContext context, List<DownloadTask> tasks) {
    if (tasks.isEmpty) {
      return _buildEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'Chưa có video nào đã tải',
        subtitle: 'Dán liên kết video để bắt đầu tải về máy.',
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
                        ? 'Đã lưu video vào Album ảnh!'
                        : 'Không thể lưu vào Album. Vui lòng cấp quyền.',
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          onShare: () => context.read<DownloadProvider>().shareFile(task),
          onOpenExternal: () =>
              context.read<DownloadProvider>().openFile(task),
          onDelete: () => _confirmDelete(context, task),
          onRetry: () => context.read<DownloadProvider>().retryTask(task),
        );
      },
    );
  }

  Widget _buildTaskList(BuildContext context, List<DownloadTask> tasks,
      {bool isAll = false}) {
    if (tasks.isEmpty) {
      return _buildEmptyState(
        icon: Icons.video_library_outlined,
        title: 'Danh sách tải về trống',
        subtitle: 'Bạn chưa tải video nào. Hãy bắt đầu ngay!',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        if (task.isActive) {
          return ActiveDownloadCard(
            task: task,
            onCancel: () =>
                context.read<DownloadProvider>().cancelTask(task.id),
          );
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
                          ? 'Đã lưu video vào Album ảnh!'
                          : 'Không thể lưu vào Album.',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            onShare: () => context.read<DownloadProvider>().shareFile(task),
            onOpenExternal: () =>
                context.read<DownloadProvider>().openFile(task),
            onDelete: () => _confirmDelete(context, task),
            onRetry: () => context.read<DownloadProvider>().retryTask(task),
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
              label: const Text('Tải video mới'),
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
