import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/session_provider.dart';
import '../utils/theme.dart';

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
                  onTap: () => _showQualityDialog(context),
                ),
                _ToolbarAction(
                  icon: Icons.fullscreen_rounded,
                  label: '全屏',
                  iconSize: iconSize,
                  fontSize: fontSize,
                  hPadding: hPadding,
                  vPadding: vPadding,
                  onTap: () => _toggleFullscreen(context),
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
                  icon: Icons.privacy_tip_outlined,
                  label: '隐私屏',
                  iconSize: iconSize,
                  fontSize: fontSize,
                  hPadding: hPadding,
                  vPadding: vPadding,
                  onTap: () => _togglePrivacyScreen(context),
                ),
                _ToolbarAction(
                  icon: Icons.fiber_manual_record,
                  label: '录屏',
                  iconSize: iconSize,
                  fontSize: fontSize,
                  hPadding: hPadding,
                  vPadding: vPadding,
                  color: context.watch<SessionProvider>().isRecording
                      ? const Color(0xFFFF5252)
                      : Colors.white,
                  onTap: () => _toggleRecording(context),
                ),
                _ToolbarAction(
                  icon: Icons.monitor,
                  label: '显示器',
                  iconSize: iconSize,
                  fontSize: fontSize,
                  hPadding: hPadding,
                  vPadding: vPadding,
                  onTap: () => _showMonitorPicker(context),
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

  void _showQualityDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _QualitySettingsSheet(),
    );
  }

  void _togglePrivacyScreen(BuildContext context) {
    final session = context.read<SessionProvider>();
    session.togglePrivacyScreen();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(session.privacyScreenOn ? '隐私屏已开启' : '隐私屏已关闭'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 800),
      ),
    );
  }

  void _toggleRecording(BuildContext context) {
    final session = context.read<SessionProvider>();
    session.toggleRecording();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(session.isRecording ? '录屏已开始' : '录屏已停止'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 800),
      ),
    );
  }

  void _showMonitorPicker(BuildContext context) {
    final session = context.read<SessionProvider>();
    final monitors = session.availableMonitors;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1E2D) : Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.monitor,
                          color: AppTheme.primaryBlue, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '选择显示器',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              ...List.generate(monitors.length, (i) {
                return RadioListTile<int>(
                  value: i,
                  groupValue: session.currentMonitor,
                  title: Text(monitors[i]),
                  subtitle: Text('显示器 ${i + 1}'),
                  onChanged: (val) {
                    if (val != null) {
                      session.setMonitor(val);
                    }
                    Navigator.pop(ctx);
                  },
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

/// Quality options used by both the bottom sheet and the desktop sidebar.
const qualityOptions = [
  ('auto', '自适应', '根据网络自动调节'),
  ('high', '高清', '原始分辨率，高流量'),
  ('medium', '标清', '降低分辨率，平衡体验'),
  ('low', '流畅', '最低画质，优先流畅度'),
];

/// Reusable quality settings content — embeddable in a sidebar or bottom sheet.
class QualitySettingsContent extends StatefulWidget {
  /// If true, shows a bottom sheet-style drag handle and header.
  final bool showHeader;

  /// If true, shows the "应用设置" button that pops the navigator.
  final bool showApplyButton;

  const QualitySettingsContent({
    super.key,
    this.showHeader = false,
    this.showApplyButton = false,
  });

  @override
  State<QualitySettingsContent> createState() => _QualitySettingsContentState();
}

class _QualitySettingsContentState extends State<QualitySettingsContent> {
  String _quality = 'auto';
  int _fps = 30;

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionProvider>();
    _quality = session.qualityPreset;
    _fps = session.fpsLimit;
  }

  void _apply() {
    context.read<SessionProvider>().setQualityPreset(_quality, _fps);
    if (widget.showApplyButton) {
      Navigator.pop(context);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '画质已设为 ${qualityOptions.firstWhere((o) => o.$1 == _quality).$2}，帧率 $_fps FPS'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showHeader) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.high_quality_outlined,
                      color: AppTheme.primaryBlue, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  '画质设置',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],

        // Quality options
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            children: qualityOptions.map((opt) {
              final selected = _quality == opt.$1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: selected
                      ? AppTheme.primaryBlue.withValues(alpha: 0.1)
                      : (isDark
                          ? const Color(0xFF242A3D)
                          : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () {
                      setState(() => _quality = opt.$1);
                      _apply();
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: selected ? AppTheme.primaryBlue : Colors.grey,
                            size: 20,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(opt.$2,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: selected
                                          ? AppTheme.primaryBlue
                                          : null,
                                    )),
                                const SizedBox(height: 2),
                                Text(opt.$3,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.white54
                                          : AppTheme.textMuted,
                                    )),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // FPS slider
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Row(
            children: [
              Text('帧率',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : AppTheme.textMuted,
                  )),
              Expanded(
                child: Slider(
                  value: _fps.toDouble(),
                  min: 5,
                  max: 60,
                  divisions: 11,
                  label: '$_fps FPS',
                  onChanged: (v) {
                    setState(() => _fps = v.round());
                    _apply();
                  },
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  '$_fps FPS',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),

        if (widget.showApplyButton)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _apply,
                child: const Text('应用设置'),
              ),
            ),
          ),
      ],
    );
  }
}

class _QualitySettingsSheet extends StatelessWidget {
  const _QualitySettingsSheet();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1E2D) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: const QualitySettingsContent(
        showHeader: true,
        showApplyButton: true,
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
