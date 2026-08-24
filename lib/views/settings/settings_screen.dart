import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../l10n/l10n.dart';
import '../../providers/download_provider.dart';
import '../../providers/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = context.watch<SettingsProvider>();
    final hasActiveDownloads = context.select<DownloadProvider, bool>(
      (provider) =>
          provider.activeTasks.isNotEmpty || provider.pausedTasks.isNotEmpty,
    );
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(title: l10n.languageSection, isDark: isDark),
          Material(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
            ),
            child: Column(
              children: [
                _LocaleRadioTile(
                  title: l10n.languageSystem,
                  value: null,
                  groupValue: settings.locale,
                  onChanged: settings.setLocale,
                ),
                const Divider(height: 1),
                _LocaleRadioTile(
                  title: l10n.languageEnglish,
                  value: const Locale('en'),
                  groupValue: settings.locale,
                  onChanged: settings.setLocale,
                ),
                const Divider(height: 1),
                _LocaleRadioTile(
                  title: l10n.languageVietnamese,
                  value: const Locale('vi'),
                  groupValue: settings.locale,
                  onChanged: settings.setLocale,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          _SectionHeader(title: l10n.appearanceSection, isDark: isDark),
          Material(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
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
                  title: l10n.themeDark,
                  icon: Icons.dark_mode_rounded,
                  value: ThemeMode.dark,
                  groupValue: settings.themeMode,
                  onChanged: (val) => settings.setThemeMode(val!),
                ),
                const Divider(height: 1),
                _ThemeRadioTile(
                  title: l10n.themeLight,
                  icon: Icons.light_mode_rounded,
                  value: ThemeMode.light,
                  groupValue: settings.themeMode,
                  onChanged: (val) => settings.setThemeMode(val!),
                ),
                const Divider(height: 1),
                _ThemeRadioTile(
                  title: l10n.themeSystem,
                  icon: Icons.brightness_auto_rounded,
                  value: ThemeMode.system,
                  groupValue: settings.themeMode,
                  onChanged: (val) => settings.setThemeMode(val!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 2. Chất lượng tải mặc định (Default Preferred Quality)
          _SectionHeader(title: l10n.qualitySection, isDark: isDark),
          Material(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
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
                _QualityRadioTile(
                  title: l10n.qualityHighestTitle,
                  subtitle: l10n.qualityHighestDescription,
                  icon: Icons.hd_rounded,
                  value: 'Highest',
                  groupValue: settings.preferredQuality,
                  onChanged: (val) => settings.setPreferredQuality(val!),
                ),
                const Divider(height: 1),
                _QualityRadioTile(
                  title: l10n.quality720Title,
                  subtitle: l10n.quality720Description,
                  icon: Icons.high_quality_rounded,
                  value: '720p',
                  groupValue: settings.preferredQuality,
                  onChanged: (val) => settings.setPreferredQuality(val!),
                ),
                const Divider(height: 1),
                _QualityRadioTile(
                  title: l10n.quality480Title,
                  subtitle: l10n.quality480Description,
                  icon: Icons.sd_rounded,
                  value: '480p',
                  groupValue: settings.preferredQuality,
                  onChanged: (val) => settings.setPreferredQuality(val!),
                ),
                const Divider(height: 1),
                _QualityRadioTile(
                  title: l10n.quality360Title,
                  subtitle: l10n.quality360Description,
                  icon: Icons.data_saver_on_rounded,
                  value: '360p',
                  groupValue: settings.preferredQuality,
                  onChanged: (val) => settings.setPreferredQuality(val!),
                ),
                const Divider(height: 1),
                _QualityRadioTile(
                  title: l10n.qualityAudioTitle,
                  subtitle: l10n.qualityAudioDescription,
                  icon: Icons.music_note_rounded,
                  value: 'Audio',
                  groupValue: settings.preferredQuality,
                  onChanged: (val) => settings.setPreferredQuality(val!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 3. Tải về & Lưu trữ (Download & Storage)
          _SectionHeader(title: l10n.downloadStorageSection, isDark: isDark),
          Material(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
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
                  secondary: const Icon(
                    Icons.photo_library_outlined,
                    color: AppColors.primary,
                  ),
                  title: Text(l10n.autoSaveGallery),
                  subtitle: Text(
                    l10n.autoSaveGalleryDescription,
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: settings.autoSaveGallery,
                  onChanged: (val) => settings.setAutoSaveGallery(val),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(
                    Icons.delete_sweep_outlined,
                    color: AppColors.primary,
                  ),
                  title: Text(l10n.removeCacheAfterGallery),
                  subtitle: Text(
                    l10n.removeCacheAfterGalleryDescription,
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: settings.removeCacheAfterGallery,
                  onChanged: settings.autoSaveGallery
                      ? settings.setRemoveCacheAfterGallery
                      : null,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(
                    Icons.cloud_outlined,
                    color: AppColors.primary,
                  ),
                  title: Text(l10n.allowExternalServices),
                  subtitle: Text(
                    l10n.allowExternalServicesDescription,
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: settings.allowExternalServices,
                  onChanged: settings.setAllowExternalServices,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.multiple_stop_rounded,
                    color: AppColors.primary,
                  ),
                  title: Text(l10n.concurrentDownloads),
                  subtitle: Text(
                    l10n.concurrentDownloadsDescription,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: DropdownButton<int>(
                    value: settings.maxConcurrentDownloads,
                    underline: const SizedBox.shrink(),
                    items: const [1, 2, 3, 4, 5]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text('$value'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) async {
                      if (value != null) {
                        await settings.setMaxConcurrentDownloads(value);
                      }
                    },
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(
                    Icons.content_paste_rounded,
                    color: AppColors.primary,
                  ),
                  title: Text(l10n.autoDetectClipboard),
                  subtitle: Text(
                    l10n.autoDetectClipboardDescription,
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: settings.autoPasteClipboard,
                  onChanged: (val) => settings.setAutoPasteClipboard(val),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.cleaning_services_rounded,
                    color: AppColors.warning,
                  ),
                  title: Text(l10n.downloadedMediaSize),
                  subtitle: Text(
                    Formatters.formatBytes(settings.cacheSizeBytes),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: hasActiveDownloads
                        ? null
                        : () async {
                            final downloadProvider = context
                                .read<DownloadProvider>();
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text(l10n.clearCacheTitle),
                                content: Text(l10n.clearCacheMessage),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: Text(l10n.cancel),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.error,
                                    ),
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: Text(l10n.deleteAll),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await downloadProvider.clearDownloadedFiles();
                              await settings.refreshCacheSize();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(l10n.cacheCleared),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            }
                          },
                    child: Text(
                      l10n.cleanUp,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 4. Thông tin ứng dụng (About)
          _SectionHeader(title: l10n.aboutSection, isDark: isDark),
          Material(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
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
                  leading: const Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.primary,
                  ),
                  title: Text(l10n.version),
                  trailing: FutureBuilder<PackageInfo>(
                    future: _packageInfo,
                    builder: (_, snapshot) => Text(
                      snapshot.data?.version ?? '—',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.support_rounded,
                    color: AppColors.accent,
                  ),
                  title: Text(l10n.supportedPlatforms),
                  subtitle: Text(
                    l10n.supportedPlatformsDescription,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.code_rounded,
                    color: AppColors.primary,
                  ),
                  title: Text(l10n.githubSource),
                  subtitle: const Text(
                    'github.com/vannt-dev/nimbleclip',
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

class _LocaleRadioTile extends StatelessWidget {
  final String title;
  final Locale? value;
  final Locale? groupValue;
  final ValueChanged<Locale?> onChanged;

  const _LocaleRadioTile({
    required this.title,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value?.languageCode == groupValue?.languageCode;
    return ListTile(
      leading: Icon(
        value == null ? Icons.language_rounded : Icons.translate_rounded,
        color: isSelected ? AppColors.primary : null,
      ),
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

class _QualityRadioTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String value;
  final String groupValue;
  final ValueChanged<String?> onChanged;

  const _QualityRadioTile({
    required this.title,
    required this.subtitle,
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
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: isSelected
          ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
          : const Icon(Icons.circle_outlined, color: Colors.grey, size: 20),
      onTap: () => onChanged(value),
    );
  }
}
