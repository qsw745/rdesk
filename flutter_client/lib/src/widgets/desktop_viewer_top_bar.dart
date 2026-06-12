import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';
import '../utils/theme.dart';
import 'connection_timer.dart';

/// Desktop-style top bar with monitor tabs, connection timer, and control center toggle.
class DesktopViewerTopBar extends StatelessWidget {
  final String sessionId;
  final bool isSidebarOpen;
  final VoidCallback onToggleSidebar;

  const DesktopViewerTopBar({
    super.key,
    required this.sessionId,
    required this.isSidebarOpen,
    required this.onToggleSidebar,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final session = context.watch<SessionProvider>();
    final monitors = session.availableMonitors;
    final currentMonitor = session.currentMonitor;
    final latency = session.currentSession?.latencyMs;
    final isOnline = session.isRemoteOnline;
    final connectedAt = session.currentSession?.connectedAt;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF151822).withValues(alpha: 0.92)
                : Colors.white.withValues(alpha: 0.92),
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.08),
              ),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),

              // Monitor tabs
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ...List.generate(monitors.length, (i) {
                        final isActive = i == currentMonitor;
                        return _MonitorTab(
                          label: monitors[i],
                          isActive: isActive,
                          isDark: isDark,
                          onTap: () => session.setMonitor(i),
                          onClose: monitors.length > 1
                              ? () {} // placeholder for future tab close
                              : null,
                        );
                      }),
                      // "+" button for adding monitor
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: IconButton(
                            onPressed: () {},
                            icon: Icon(
                              Icons.add,
                              size: 16,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                            padding: EdgeInsets.zero,
                            splashRadius: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Connection timer
              if (connectedAt != null) ...[
                Icon(
                  Icons.signal_cellular_alt,
                  size: 14,
                  color: _signalColor(latency, isOnline),
                ),
                const SizedBox(width: 6),
                ConnectionTimer(
                  startTime: connectedAt,
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black54,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],

              const SizedBox(width: 16),

              // Control center button
              _ControlCenterButton(
                isOpen: isSidebarOpen,
                isDark: isDark,
                onTap: onToggleSidebar,
              ),

              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  Color _signalColor(int? latency, bool online) {
    if (!online) return Colors.redAccent;
    if (latency == null) return Colors.white38;
    if (latency < 50) return Colors.greenAccent;
    if (latency < 150) return Colors.amberAccent;
    return Colors.redAccent;
  }
}

class _MonitorTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  const _MonitorTab({
    required this.label,
    required this.isActive,
    required this.isDark,
    required this.onTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        margin: const EdgeInsets.only(right: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isActive
              ? (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.04))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isActive
              ? const Border(
                  bottom: BorderSide(
                    color: AppTheme.primaryBlue,
                    width: 2,
                  ),
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.monitor,
              size: 14,
              color: isActive
                  ? (isDark ? Colors.white : Colors.black87)
                  : (isDark ? Colors.white38 : Colors.black38),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive
                    ? (isDark ? Colors.white : Colors.black87)
                    : (isDark ? Colors.white54 : Colors.black54),
              ),
            ),
            if (onClose != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onClose,
                child: Icon(
                  Icons.close,
                  size: 12,
                  color: isDark ? Colors.white24 : Colors.black26,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ControlCenterButton extends StatelessWidget {
  final bool isOpen;
  final bool isDark;
  final VoidCallback onTap;

  const _ControlCenterButton({
    required this.isOpen,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isOpen
          ? AppTheme.primaryBlue.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.dashboard_customize_outlined,
                size: 16,
                color: isOpen
                    ? AppTheme.primaryBlue
                    : (isDark ? Colors.white54 : Colors.black54),
              ),
              const SizedBox(width: 6),
              Text(
                '控制中心',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isOpen
                      ? AppTheme.primaryBlue
                      : (isDark ? Colors.white54 : Colors.black54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
