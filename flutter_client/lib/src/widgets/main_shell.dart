import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../utils/theme.dart';

/// Persistent bottom navigation shell.
class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.04),
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.3)
                      : Colors.black.withValues(alpha: 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavButton(
                  icon: Icons.home_rounded,
                  activeIcon: Icons.home_rounded,
                  label: '首页',
                  active: navigationShell.currentIndex == 0,
                  onTap: () => navigationShell.goBranch(
                    0,
                    initialLocation: 0 == navigationShell.currentIndex,
                  ),
                ),
                _NavButton(
                  icon: Icons.history_rounded,
                  activeIcon: Icons.history_rounded,
                  label: '历史',
                  active: navigationShell.currentIndex == 1,
                  onTap: () => navigationShell.goBranch(
                    1,
                    initialLocation: 1 == navigationShell.currentIndex,
                  ),
                ),
                _NavButton(
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings_rounded,
                  label: '设置',
                  active: navigationShell.currentIndex == 2,
                  onTap: () => navigationShell.goBranch(
                    2,
                    initialLocation: 2 == navigationShell.currentIndex,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  const _NavButton({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = active
        ? AppTheme.primaryBlue
        : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.primaryBlue.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: active ? 1.1 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                active ? activeIcon : icon,
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
