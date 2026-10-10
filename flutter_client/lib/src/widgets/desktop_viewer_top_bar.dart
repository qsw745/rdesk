import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';
import '../utils/theme.dart';
import 'connection_timer.dart';
import 'remote_display_tabs.dart';

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

              // One tab per screen of the other computer; scrolls sideways
              // when there are more than fit.
              const Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: RemoteDisplayTabs(),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Connection timer
              if (connectedAt != null) ...[
                Icon(
                  Icons.signal_cellular_alt,
                  size: 14,
                  color: _signalColor(latency, isOnline, isDark),
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

  Color _signalColor(int? latency, bool online, bool isDark) {
    if (!online) return Colors.redAccent;
    // Not measured yet: neutral, and visible on a light bar too.
    if (latency == null) return isDark ? Colors.white38 : Colors.black38;
    if (latency < 50) return isDark ? Colors.greenAccent : Colors.green;
    if (latency < 150) return isDark ? Colors.amberAccent : Colors.orange;
    return Colors.redAccent;
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
