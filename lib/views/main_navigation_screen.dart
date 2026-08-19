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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeDownloadsCount =
        context.watch<DownloadProvider>().activeTasks.length;

    final screens = [
      HomeScreen(
        onNavigateDownloads: () => setState(() => _currentIndex = 1),
      ),
      DownloadsScreen(
        onNavigateHome: () => setState(() => _currentIndex = 0),
      ),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
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
              selectedIcon: const Icon(Icons.home_rounded, color: AppColors.primary),
              label: context.l10n.navHome,
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: activeDownloadsCount > 0,
                label: Text('$activeDownloadsCount'),
                backgroundColor: AppColors.primary,
                child: const Icon(Icons.download_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: activeDownloadsCount > 0,
                label: Text('$activeDownloadsCount'),
                backgroundColor: AppColors.primary,
                child: const Icon(Icons.download_rounded, color: AppColors.primary),
              ),
              label: context.l10n.navDownloads,
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings_rounded, color: AppColors.primary),
              label: context.l10n.navSettings,
            ),
          ],
        ),
      ),
    );
  }
}
