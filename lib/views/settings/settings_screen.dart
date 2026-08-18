import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/formatters.dart';
import '../../providers/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Giao diện (Theme)
          _SectionHeader(title: 'Giao diện ứng dụng', isDark: isDark),
          Material(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                width: 1,
              ),
            ),
            child: Column(
              children: [
                _ThemeRadioTile(
                  title: 'Giao diện tối (Dark)',
                  icon: Icons.dark_mode_rounded,
                  value: ThemeMode.dark,
                  groupValue: settings.themeMode,
                  onChanged: (val) => settings.setThemeMode(val!),
                ),
                const Divider(height: 1),
                _ThemeRadioTile(
                  title: 'Giao diện sáng (Light)',
                  icon: Icons.light_mode_rounded,
                  value: ThemeMode.light,
                  groupValue: settings.themeMode,
                  onChanged: (val) => settings.setThemeMode(val!),
                ),
                const Divider(height: 1),
                _ThemeRadioTile(
                  title: 'Theo hệ thống (System)',
                  icon: Icons.brightness_auto_rounded,
                  value: ThemeMode.system,
                  groupValue: settings.themeMode,
                  onChanged: (val) => settings.setThemeMode(val!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 2. Tải về & Lưu trữ (Download & Storage)
          _SectionHeader(title: 'Tải về & Lưu trữ', isDark: isDark),
          Material(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                width: 1,
              ),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.photo_library_outlined,
                      color: AppColors.primary),
                  title: const Text('Tự động lưu vào Album ảnh'),
                  subtitle: const Text(
                    'Lưu trực tiếp vào Thư viện sau khi tải xong',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: settings.autoSaveGallery,
                  onChanged: (val) => settings.setAutoSaveGallery(val),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.content_paste_rounded,
                      color: AppColors.primary),
                  title: const Text('Tự động nhận diện Clipboard'),
                  subtitle: const Text(
                    'Tự động kiểm tra liên kết video khi mở ứng dụng',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: settings.autoPasteClipboard,
                  onChanged: (val) => settings.setAutoPasteClipboard(val),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_rounded,
                      color: AppColors.warning),
                  title: const Text('Dung lượng video đã tải'),
                  subtitle: Text(
                    Formatters.formatBytes(settings.cacheSizeBytes),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: AppColors.primary),
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Xóa bộ nhớ cache?'),
                          content: const Text(
                            'Toàn bộ video đã tải trong thư mục ứng dụng sẽ bị xóa.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Hủy'),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.error),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Xóa tất cả'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await settings.clearCache();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Đã dọn dẹp bộ nhớ tạm.'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
                    child: const Text(
                      'Dọn dẹp',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 3. Thông tin ứng dụng (About)
          _SectionHeader(title: 'Thông tin ứng dụng', isDark: isDark),
          Material(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                width: 1,
              ),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded,
                      color: AppColors.primary),
                  title: const Text('Phiên bản'),
                  trailing: Text(
                    AppConstants.appVersion,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.support_rounded, color: AppColors.accent),
                  title: Text('Nền tảng hỗ trợ'),
                  subtitle: Text(
                    'YouTube, TikTok (No Watermark), Facebook, Twitter/X, v.v.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.code_rounded, color: AppColors.primary),
                  title: const Text('Mã nguồn GitHub'),
                  subtitle: const Text(
                    'github.com/vannt-dev/snap-video',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool isDark;

  const _SectionHeader({required this.title, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: isDark
              ? AppColors.darkTextSecondary
              : AppColors.lightTextSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ThemeRadioTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final ThemeMode value;
  final ThemeMode groupValue;
  final ValueChanged<ThemeMode?> onChanged;

  const _ThemeRadioTile({
    required this.title,
    required this.icon,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == groupValue;
    return ListTile(
      leading: Icon(icon, color: isSelected ? AppColors.primary : null),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
          : const Icon(Icons.circle_outlined, color: Colors.grey, size: 20),
      onTap: () => onChanged(value),
    );
  }
}
