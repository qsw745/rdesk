import 'package:flutter/material.dart';

class RemoteToolbar extends StatelessWidget {
  final String sessionId;
  final VoidCallback onDisconnect;
  final VoidCallback onFileManager;
  final VoidCallback onChat;
  final VoidCallback onToggleToolbar;

  const RemoteToolbar({
    super.key,
    required this.sessionId,
    required this.onDisconnect,
    required this.onFileManager,
    required this.onChat,
    required this.onToggleToolbar,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                sessionId,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            _ToolbarAction(
              icon: Icons.high_quality_outlined,
              label: '画质',
              onTap: () => _showTip(context, '画质调节稍后接入'),
            ),
            _ToolbarAction(
              icon: Icons.fullscreen,
              label: '全屏',
              onTap: () => _showTip(context, '全屏切换稍后接入'),
            ),
            _ToolbarAction(
              onTap: onFileManager,
              icon: Icons.folder_open,
              label: '文件',
            ),
            _ToolbarAction(
              onTap: onChat,
              icon: Icons.chat_bubble_outline,
              label: '聊天',
            ),
            _ToolbarAction(
              onTap: onToggleToolbar,
              icon: Icons.visibility_off_outlined,
              label: '隐藏',
            ),
            _ToolbarAction(
              onTap: onDisconnect,
              icon: Icons.link_off,
              label: '断开',
              color: Colors.redAccent,
            ),
          ],
        ),
      ),
    );
  }

  void _showTip(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _ToolbarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _ToolbarAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: color, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
