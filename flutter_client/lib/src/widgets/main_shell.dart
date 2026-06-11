import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../utils/theme.dart';

class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  static const _tabs = [
    _TabMeta(
      icon: Icons.devices_other_outlined,
      activeIcon: Icons.devices_other,
      label: '设备列表',
    ),
    _TabMeta(
      icon: Icons.cloud_outlined,
      activeIcon: Icons.cloud,
      label: '云设备',
    ),
    _TabMeta(
      icon: Icons.connected_tv_outlined,
      activeIcon: Icons.connected_tv,
      label: '远程连接',
    ),
    _TabMeta(
      icon: Icons.contacts_outlined,
      activeIcon: Icons.contacts,
      label: '地址簿',
    ),
    _TabMeta(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person,
      label: '我的',
    ),
  ];

  void _onTabTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final useRail = screenWidth >= 768;

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            _DesktopRail(
              currentIndex: navigationShell.currentIndex,
              isDark: isDark,
              extended: screenWidth >= 1200,
              onTap: _onTabTap,
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.06),
            ),
            Expanded(child: navigationShell),
          ],
        ),
      );
    }

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: _BottomBar(
        currentIndex: navigationShell.currentIndex,
        isDark: isDark,
        onTap: _onTabTap,
      ),
    );
  }
}

class _TabMeta {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _TabMeta({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

class _BottomBar extends StatelessWidget {
  final int currentIndex;
  final bool isDark;
  final ValueChanged<int> onTap;

  const _BottomBar({
    required this.currentIndex,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(4, 8, 4, 6 + bottomPadding),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171A24) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(
          MainShell._tabs.length,
          (i) => _NavButton(
            meta: MainShell._tabs[i],
            active: currentIndex == i,
            isDark: isDark,
            onTap: () => onTap(i),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final _TabMeta meta;
  final bool active;
  final bool isDark;
  final VoidCallback onTap;

  const _NavButton({
    required this.meta,
    required this.active,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const activeColor = AppTheme.primaryBlue;
    final inactiveColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : const Color(0xFF9E9E9E);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: active ? 16 : 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: active
                    ? activeColor.withValues(alpha: 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                active ? meta.activeIcon : meta.icon,
                color: active ? activeColor : inactiveColor,
                size: active ? 24 : 22,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              meta.label,
              style: TextStyle(
                color: active ? activeColor : inactiveColor,
                fontSize: 10,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopRail extends StatelessWidget {
  final int currentIndex;
  final bool isDark;
  final bool extended;
  final ValueChanged<int> onTap;

  const _DesktopRail({
    required this.currentIndex,
    required this.isDark,
    required this.extended,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: currentIndex,
      onDestinationSelected: onTap,
      extended: extended,
      minWidth: 72,
      minExtendedWidth: 200,
      backgroundColor: isDark ? const Color(0xFF171A24) : Colors.white,
      indicatorColor: AppTheme.primaryBlue.withValues(alpha: 0.12),
      selectedIconTheme: const IconThemeData(color: AppTheme.primaryBlue),
      unselectedIconTheme: IconThemeData(
        color: Theme.of(context)
            .colorScheme
            .onSurfaceVariant
            .withValues(alpha: 0.55),
      ),
      selectedLabelTextStyle: const TextStyle(
        color: AppTheme.primaryBlue,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
      unselectedLabelTextStyle: TextStyle(
        color: Theme.of(context)
            .colorScheme
            .onSurfaceVariant
            .withValues(alpha: 0.6),
        fontSize: 13,
      ),
      labelType: extended
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      leading: Padding(
        padding: EdgeInsets.symmetric(
          vertical: 20,
          horizontal: extended ? 16 : 0,
        ),
        child: extended
            ? Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: AppTheme.brandGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.connected_tv_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'RDesk',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              )
            : Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: AppTheme.brandGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.connected_tv_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
      ),
      destinations: MainShell._tabs.map((tab) {
        return NavigationRailDestination(
          icon: Icon(tab.icon),
          selectedIcon: Icon(tab.activeIcon),
          label: Text(tab.label),
        );
      }).toList(),
    );
  }
}
