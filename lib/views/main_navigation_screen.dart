import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../l10n/l10n.dart';
import '../providers/download_provider.dart';
import 'downloads/downloads_screen.dart';
import 'home/home_screen.dart';
import 'settings/settings_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      HomeScreen(onNavigateDownloads: () => setState(() => _currentIndex = 1)),
      DownloadsScreen(onNavigateHome: () => setState(() => _currentIndex = 0)),
      const SettingsScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          border: Border(
            top: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              width: 1,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() => _currentIndex = index);
          },
          backgroundColor: Colors.transparent,
          indicatorColor: AppColors.primary.withAlpha(isDark ? 50 : 30),
          elevation: 0,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(
                Icons.home_rounded,
                color: AppColors.primary,
              ),
              label: context.l10n.navHome,
            ),
            NavigationDestination(
              icon: const _DownloadBadge(selected: false),
              selectedIcon: const _DownloadBadge(selected: true),
              label: context.l10n.navDownloads,
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(
                Icons.settings_rounded,
                color: AppColors.primary,
              ),
              label: context.l10n.navSettings,
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadBadge extends StatelessWidget {
  const _DownloadBadge({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Selector<DownloadProvider, int>(
      selector: (_, provider) => provider.activeTasks.length,
      builder: (_, count, _) => Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        backgroundColor: AppColors.primary,
        child: Icon(
          selected ? Icons.download_rounded : Icons.download_outlined,
          color: selected ? AppColors.primary : null,
        ),
      ),
    );
  }
}
