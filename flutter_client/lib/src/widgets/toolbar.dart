import 'dart:ui';
import 'package:flutter/material.dart';

class RemoteToolbar extends StatelessWidget {
  final String sessionId;
  final VoidCallback onDisconnect;
  final VoidCallback onFileManager;
  final VoidCallback onChat;
  final VoidCallback onToggleToolbar;
  final Future<void> Function(String action) onRemoteAction;
  final Future<void> Function() onRemoteTextInput;
  final Future<void> Function() onPushClipboard;
  final Future<void> Function() onPullClipboard;

  const RemoteToolbar({
    super.key,
    required this.sessionId,
    required this.onDisconnect,
    required this.onFileManager,
    required this.onChat,
    required this.onToggleToolbar,
    required this.onRemoteAction,
    required this.onRemoteTextInput,
    required this.onPushClipboard,
    required this.onPullClipboard,
  });

  @override
  Widget build(BuildContext context) {
    final shortest = MediaQuery.of(context).size.shortestSide;

    final double iconSize;
    final double fontSize;
    final double hPadding;
    final double vPadding;
    if (shortest < 600) {
      iconSize = 18;
      fontSize = 10;
      hPadding = 8;
      vPadding = 6;
    } else if (shortest < 900) {
      iconSize = 22;
      fontSize = 12;
      hPadding = 10;
      vPadding = 8;
    } else {
      iconSize = 24;
      fontSize = 13;
      hPadding = 12;
      vPadding = 10;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(
                horizontal: hPadding + 4, vertical: vPadding + 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPadding),
                  child: Text(
                    sessionId,
                    style: TextStyle(
                        color: Colors.white54, fontSize: fontSize),
                  ),
                ),
                _ToolbarAction(
                  icon: Icons.arrow_back_rounded,
                  label: '返回',
                  iconSize: iconSize,
                  fontSize: fontSize,
                  hPadding: hPadding,
                  vPadding: vPadding,
                  onTap: () => onRemoteAction('back'),
                ),
                _ToolbarAction(
                  icon: Icons.home_rounded,
                  label: '主页',
                  iconSize: iconSize,
                  fontSize: fontSize,
                  hPadding: hPadding,
                  vPadding: vPadding,
                  onTap: () => onRemoteAction('home'),
                ),
                _ToolbarAction(
                  icon: Icons.apps_rounded,
                  label: '任务',
                  iconSize: iconSize,
                  fontSize: fontSize,
                  hPadding: hPadding,
                  vPadding: vPadding,
                  onTap: () => onRemoteAction('recents'),
                ),
                _ToolbarAction(
                  icon: Icons.screen_lock_portrait_rounded,
                  label: '唤醒',
                  iconSize: iconSize,
                  fontSize: fontSize,
                  hPadding: hPadding,
                  vPadding: vPadding,
                  color: Colors.amberAccent,
                  onTap: () => onRemoteAction('wake_screen'),
                ),
                _ToolbarAction(
                  icon: Icons.keyboard_arrow_up_rounded,
                  label: '上滑',
                  iconSize: iconSize,
                  fontSize: fontSize,
                  hPadding: hPadding,
                  vPadding: vPadding,
                  onTap: () => onRemoteAction('scroll_up'),
                ),
                _ToolbarAction(
                  icon: Icons.keyboard_arrow_down_rounded,
                  label: '下滑',
                  iconSize: iconSize,
                  fontSize: fontSize,
                  hPadding: hPadding,
                  vPadding: vPadding,
                  onTap: () => onRemoteAction('scroll_down'),
                ),
                _ToolbarAction(
                  icon: Icons.keyboard_rounded,
                  label: '输入',
                  iconSize: iconSize,
                  fontSize: fontSize,
                  hPadding: hPadding,
                  vPadding: vPadding,
                  onTap: onRemoteTextInput,
                ),
                _ToolbarAction(
                  icon: Icons.backspace_outlined,
                  label: '删除',
                  iconSize: iconSize,
                  fontSize: fontSize,
                  hPadding: hPadding,
                  vPadding: vPadding,
                  onTap: () => onRemoteAction('delete'),
                ),
                _ToolbarAction(
                  icon: Icons.keyboard_return_rounded,
                  label: '回车',
                  iconSize: iconSize,
                  fontSize: fontSize,
                  hPadding: hPadding,
                  vPadding: vPadding,
                  onTap: () => onRemoteAction('enter'),
                ),
                _ToolbarAction(
                  icon: Icons.upload_rounded,
                  label: '推板',
                  iconSize: iconSize,
                  fontSize: fontSize,
                  hPadding: hPadding,
                  vPadding: vPadding,
                  onTap: onPushClipboard,
                ),
                _ToolbarAction(
                  icon: Icons.download_rounded,
                  label: '拉板',
                  iconSize: iconSize,
                  fontSize: fontSize,
                  hPadding: hPadding,
                  vPadding: vPadding,
                  onTap: onPullClipboard,
                ),
                _ToolbarAction(
                  icon: Icons.high_quality_outlined,
                  label: '画质',
                  iconSize: iconSize,
                  fontSize: fontSize,
                  hPadding: hPadding,
                  vPadding: vPadding,
                  onTap: () => _showTip(context, '画质调节稍后接入'),
                ),
                _ToolbarAction(
                  icon: Icons.fullscreen_rounded,
                  label: '全屏',
                  iconSize: iconSize,
                  fontSize: fontSize,
                  hPadding: hPadding,
                  vPadding: vPadding,
                  onTap: () => _showTip(context, '全屏切换稍后接入'),
                ),
                _ToolbarAction(
                  onTap: onFileManager,
                  icon: Icons.folder_open_rounded,
                  label: '文件',
                  iconSize: iconSize,
                  fontSize: fontSize,
                  hPadding: hPadding,
                  vPadding: vPadding,
                ),
                _ToolbarAction(
                  onTap: onChat,
                  icon: Icons.chat_bubble_outline_rounded,
                  label: '聊天',
                  iconSize: iconSize,
                  fontSize: fontSize,
                  hPadding: hPadding,
                  vPadding: vPadding,
                ),
                _ToolbarAction(
                  onTap: onToggleToolbar,
                  icon: Icons.visibility_off_outlined,
                  label: '隐藏',
                  iconSize: iconSize,
                  fontSize: fontSize,
                  hPadding: hPadding,
                  vPadding: vPadding,
                ),
                _ToolbarAction(
                  onTap: onDisconnect,
                  icon: Icons.link_off_rounded,
                  label: '断开',
                  iconSize: iconSize,
                  fontSize: fontSize,
                  hPadding: hPadding,
                  vPadding: vPadding,
                  color: Colors.redAccent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTip(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _ToolbarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final double iconSize;
  final double fontSize;
  final double hPadding;
  final double vPadding;

  const _ToolbarAction({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.iconSize,
    required this.fontSize,
    required this.hPadding,
    required this.vPadding,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: Colors.white.withValues(alpha: 0.1),
        highlightColor: Colors.white.withValues(alpha: 0.05),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: hPadding, vertical: vPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: iconSize),
              SizedBox(height: vPadding > 6 ? 4 : 2),
              Text(label,
                  style: TextStyle(color: color, fontSize: fontSize)),
            ],
          ),
        ),
      ),
    );
  }
}
