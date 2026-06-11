import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';
import 'toolbar.dart' show QualitySettingsContent;

/// Right-side control panel for the desktop remote viewer.
/// Width is controlled by the parent layout (typically 280px).
class DesktopViewerSidebar extends StatefulWidget {
  final String sessionId;
  final VoidCallback onDisconnect;
  final VoidCallback onFileManager;
  final VoidCallback onChat;
  final Future<void> Function(String action) onRemoteAction;
  final Future<void> Function() onRemoteTextInput;
  final Future<void> Function() onPushClipboard;
  final Future<void> Function() onPullClipboard;

  const DesktopViewerSidebar({
    super.key,
    required this.sessionId,
    required this.onDisconnect,
    required this.onFileManager,
    required this.onChat,
    required this.onRemoteAction,
    required this.onRemoteTextInput,
    required this.onPushClipboard,
    required this.onPullClipboard,
  });

  @override
  State<DesktopViewerSidebar> createState() => _DesktopViewerSidebarState();
}

class _DesktopViewerSidebarState extends State<DesktopViewerSidebar> {
  final Set<String> _expanded = {'peripherals'};

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final session = context.watch<SessionProvider>();
    final monitors = session.availableMonitors;
    final currentMonitor = session.currentMonitor;
    final monitorName =
        currentMonitor < monitors.length ? monitors[currentMonitor] : '主显示器';

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF151822).withValues(alpha: 0.95)
                : Colors.white.withValues(alpha: 0.95),
            border: Border(
              left: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.08),
              ),
            ),
          ),
          child: Column(
            children: [
              // Monitor name header
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.monitor,
                      size: 16,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        monitorName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // Scrollable sections
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    _buildSection(
                      key: 'quality',
                      icon: Icons.high_quality_outlined,
                      label: '画质',
                      isDark: isDark,
                      child: const QualitySettingsContent(),
                    ),
                    _buildSection(
                      key: 'window',
                      icon: Icons.fullscreen_rounded,
                      label: '窗口',
                      isDark: isDark,
                      child: _buildWindowSection(isDark),
                    ),
                    _buildSection(
                      key: 'security',
                      icon: Icons.privacy_tip_outlined,
                      label: '安全',
                      isDark: isDark,
                      child: _buildSecuritySection(isDark, session),
                    ),
                    _buildSection(
                      key: 'peripherals',
                      icon: Icons.keyboard_rounded,
                      label: '外设',
                      isDark: isDark,
                      child: _buildPeripheralsSection(isDark),
                    ),
                    _buildSection(
                      key: 'more',
                      icon: Icons.more_horiz_rounded,
                      label: '更多',
                      isDark: isDark,
                      child: _buildMoreSection(isDark, session),
                    ),
                  ],
                ),
              ),

              // Bottom action buttons
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    // Fullscreen button
                    SizedBox(
                      width: double.infinity,
                      height: 36,
                      child: OutlinedButton.icon(
                        onPressed: () => _toggleFullscreen(context),
                        icon: const Icon(Icons.fullscreen_rounded, size: 18),
                        label: const Text('进入全屏幕',
                            style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Disconnect button — always visible
                    SizedBox(
                      width: double.infinity,
                      height: 36,
                      child: FilledButton.icon(
                        onPressed: widget.onDisconnect,
                        icon:
                            const Icon(Icons.link_off_rounded, size: 18),
                        label: const Text('退出远控',
                            style: TextStyle(fontSize: 13)),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String key,
    required IconData icon,
    required String label,
    required bool isDark,
    required Widget child,
  }) {
    final isExpanded = _expanded.contains(key);
    return Column(
      children: [
        InkWell(
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expanded.remove(key);
              } else {
                _expanded.add(key);
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_right_rounded,
                  size: 18,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: child,
          ),
        Divider(
          height: 1,
          indent: 16,
          endIndent: 16,
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.04),
        ),
      ],
    );
  }

  Widget _buildWindowSection(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _SidebarActionTile(
            icon: Icons.fullscreen_rounded,
            label: '切换全屏',
            isDark: isDark,
            onTap: () => _toggleFullscreen(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSecuritySection(bool isDark, SessionProvider session) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _SidebarToggleTile(
            icon: Icons.privacy_tip_outlined,
            label: '隐私屏',
            isDark: isDark,
            value: session.privacyScreenOn,
            onChanged: (_) {
              session.togglePrivacyScreen();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      session.privacyScreenOn ? '隐私屏已开启' : '隐私屏已关闭'),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(milliseconds: 800),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPeripheralsSection(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _SidebarActionTile(
            icon: Icons.keyboard_rounded,
            label: '文本输入',
            isDark: isDark,
            onTap: widget.onRemoteTextInput,
          ),
          _SidebarActionTile(
            icon: Icons.upload_rounded,
            label: '推送剪贴板',
            isDark: isDark,
            onTap: widget.onPushClipboard,
          ),
          _SidebarActionTile(
            icon: Icons.download_rounded,
            label: '拉取剪贴板',
            isDark: isDark,
            onTap: widget.onPullClipboard,
          ),
          _SidebarActionTile(
            icon: Icons.backspace_outlined,
            label: '退格键',
            isDark: isDark,
            onTap: () => widget.onRemoteAction('delete'),
          ),
          _SidebarActionTile(
            icon: Icons.keyboard_return_rounded,
            label: '回车键',
            isDark: isDark,
            onTap: () => widget.onRemoteAction('enter'),
          ),
        ],
      ),
    );
  }

  Widget _buildMoreSection(bool isDark, SessionProvider session) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _SidebarActionTile(
            icon: Icons.fiber_manual_record,
            label: '录屏',
            isDark: isDark,
            trailing: session.isRecording
                ? Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                  )
                : null,
            onTap: () {
              session.toggleRecording();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content:
                      Text(session.isRecording ? '录屏已开始' : '录屏已停止'),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(milliseconds: 800),
                ),
              );
            },
          ),
          _SidebarActionTile(
            icon: Icons.folder_open_rounded,
            label: '文件管理',
            isDark: isDark,
            onTap: widget.onFileManager,
          ),
          _SidebarActionTile(
            icon: Icons.chat_bubble_outline_rounded,
            label: '聊天',
            isDark: isDark,
            onTap: widget.onChat,
          ),
          const SizedBox(height: 4),
          // Remote navigation actions as a compact grid
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _CompactActionChip(
                  icon: Icons.arrow_back_rounded,
                  label: '返回',
                  isDark: isDark,
                  onTap: () => widget.onRemoteAction('back'),
                ),
                _CompactActionChip(
                  icon: Icons.home_rounded,
                  label: '主页',
                  isDark: isDark,
                  onTap: () => widget.onRemoteAction('home'),
                ),
                _CompactActionChip(
                  icon: Icons.apps_rounded,
                  label: '任务',
                  isDark: isDark,
                  onTap: () => widget.onRemoteAction('recents'),
                ),
                _CompactActionChip(
                  icon: Icons.screen_lock_portrait_rounded,
                  label: '唤醒',
                  isDark: isDark,
                  onTap: () => widget.onRemoteAction('wake_screen'),
                ),
                _CompactActionChip(
                  icon: Icons.keyboard_arrow_up_rounded,
                  label: '上滑',
                  isDark: isDark,
                  onTap: () => widget.onRemoteAction('scroll_up'),
                ),
                _CompactActionChip(
                  icon: Icons.keyboard_arrow_down_rounded,
                  label: '下滑',
                  isDark: isDark,
                  onTap: () => widget.onRemoteAction('scroll_down'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggleFullscreen(BuildContext context) {
    final isFullscreen = MediaQuery.of(context).padding.top == 0;
    if (isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isFullscreen ? '已退出全屏' : '已进入全屏模式'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 800),
      ),
    );
  }
}

class _SidebarActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  final Widget? trailing;

  const _SidebarActionTile({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: isDark ? Colors.white54 : Colors.black54),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
            if (trailing != null) trailing!,
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarToggleTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SidebarToggleTile({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          Icon(icon,
              size: 16, color: isDark ? Colors.white54 : Colors.black54),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
          SizedBox(
            height: 24,
            child: Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  const _CompactActionChip({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.black.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14,
                  color: isDark ? Colors.white54 : Colors.black54),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
