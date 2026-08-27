import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';
import '../utils/theme.dart';

typedef RemoteActionCallback = Future<void> Function(String action);

class RemoteKeyboardSheet extends StatelessWidget {
  const RemoteKeyboardSheet({
    super.key,
    required this.peerOs,
    required this.onOpenSystemKeyboard,
    required this.onRemoteAction,
  });

  final String peerOs;
  final VoidCallback onOpenSystemKeyboard;
  final RemoteActionCallback onRemoteAction;

  bool get _supportsDesktopKeys => peerOs.toLowerCase().contains('mac');

  bool get _knownAndroid => peerOs.toLowerCase().contains('android');

  @override
  Widget build(BuildContext context) {
    final advancedEnabled = _supportsDesktopKeys;
    return _ToolSheet(
      title: '电脑键盘',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onOpenSystemKeyboard();
              },
              icon: const Icon(Icons.keyboard_alt_outlined),
              label: const Text('打开系统输入法'),
            ),
            const SizedBox(height: 16),
            const _ToolSectionLabel('常用按键'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _KeyButton(
                  label: 'Esc',
                  enabled: advancedEnabled,
                  onTap: () => onRemoteAction('key_escape'),
                ),
                _KeyButton(
                  label: 'Tab',
                  enabled: advancedEnabled,
                  onTap: () => onRemoteAction('key_tab'),
                ),
                _KeyButton(
                  label: '←',
                  enabled: advancedEnabled,
                  semanticsLabel: '左方向键',
                  onTap: () => onRemoteAction('key_arrow_left'),
                ),
                _KeyButton(
                  label: '↑',
                  enabled: advancedEnabled,
                  semanticsLabel: '上方向键',
                  onTap: () => onRemoteAction('key_arrow_up'),
                ),
                _KeyButton(
                  label: '↓',
                  enabled: advancedEnabled,
                  semanticsLabel: '下方向键',
                  onTap: () => onRemoteAction('key_arrow_down'),
                ),
                _KeyButton(
                  label: '→',
                  enabled: advancedEnabled,
                  semanticsLabel: '右方向键',
                  onTap: () => onRemoteAction('key_arrow_right'),
                ),
                _KeyButton(
                  label: '删除',
                  onTap: () => onRemoteAction('delete'),
                ),
                _KeyButton(
                  label: '回车',
                  onTap: () => onRemoteAction('enter'),
                ),
                _KeyButton(
                  label: '空格',
                  enabled: advancedEnabled,
                  wide: true,
                  onTap: () => onRemoteAction('key_space'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const _ToolSectionLabel('macOS 组合键'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _KeyButton(
                  label: '⌘ A',
                  enabled: advancedEnabled,
                  semanticsLabel: '全选',
                  onTap: () => onRemoteAction('key_command_a'),
                ),
                _KeyButton(
                  label: '⌘ C',
                  enabled: advancedEnabled,
                  semanticsLabel: '复制',
                  onTap: () => onRemoteAction('key_command_c'),
                ),
                _KeyButton(
                  label: '⌘ V',
                  enabled: advancedEnabled,
                  semanticsLabel: '粘贴',
                  onTap: () => onRemoteAction('key_command_v'),
                ),
                _KeyButton(
                  label: '⌘ X',
                  enabled: advancedEnabled,
                  semanticsLabel: '剪切',
                  onTap: () => onRemoteAction('key_command_x'),
                ),
                _KeyButton(
                  label: '⌘ Z',
                  enabled: advancedEnabled,
                  semanticsLabel: '撤销',
                  onTap: () => onRemoteAction('key_command_z'),
                ),
                _KeyButton(
                  label: '⇧ ⌘ Z',
                  enabled: advancedEnabled,
                  semanticsLabel: '重做',
                  onTap: () => onRemoteAction('key_command_shift_z'),
                ),
              ],
            ),
            if (!advancedEnabled) ...[
              const SizedBox(height: 14),
              Text(
                _knownAndroid
                    ? '安卓被控端暂只支持文字、删除和回车；不支持的桌面按键已停用。'
                    : '桌面按键目前仅支持 macOS 被控端；确认远端系统前保持停用。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Colors.white.withValues(alpha: 0.52),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class RemoteControlSettingsSheet extends StatefulWidget {
  const RemoteControlSettingsSheet({
    super.key,
    required this.autoHideToolbar,
    required this.onAutoHideChanged,
    required this.onToggleFullscreen,
    required this.onHideToolbar,
    required this.onRotate,
  });

  final bool autoHideToolbar;
  final ValueChanged<bool> onAutoHideChanged;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onHideToolbar;
  final VoidCallback onRotate;

  @override
  State<RemoteControlSettingsSheet> createState() =>
      _RemoteControlSettingsSheetState();
}

class _RemoteControlSettingsSheetState
    extends State<RemoteControlSettingsSheet> {
  late bool _autoHideToolbar;

  @override
  void initState() {
    super.initState();
    _autoHideToolbar = widget.autoHideToolbar;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    return _ToolSheet(
      title: '控制设置',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: Column(
          children: [
            _ToolCard(
              children: [
                SwitchListTile.adaptive(
                  value: session.viewOnly,
                  onChanged: (_) => session.toggleViewOnly(),
                  secondary: const Icon(Icons.visibility_outlined),
                  title: const Text('仅观看'),
                  subtitle: const Text('关闭所有向被控端发送的输入'),
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile.adaptive(
                  value: session.pointerMode,
                  onChanged: (_) => session.togglePointerMode(),
                  secondary: const Icon(Icons.mouse_outlined),
                  title: const Text('指针模式'),
                  subtitle: const Text('拖动虚拟指针，再点击指针所在位置'),
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile.adaptive(
                  value: _autoHideToolbar,
                  onChanged: (value) {
                    setState(() => _autoHideToolbar = value);
                    widget.onAutoHideChanged(value);
                  },
                  secondary: const Icon(Icons.visibility_off_outlined),
                  title: const Text('自动隐藏工具栏'),
                  subtitle: const Text('停止操作 5 秒后收起底部工具栏'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ToolCard(
              children: [
                _ToolActionTile(
                  icon: Icons.screen_rotation_rounded,
                  title: '旋转画面',
                  onTap: widget.onRotate,
                ),
                const Divider(height: 1, indent: 56),
                _ToolActionTile(
                  icon: Icons.fullscreen_rounded,
                  title: '进入全屏',
                  onTap: widget.onToggleFullscreen,
                ),
                const Divider(height: 1, indent: 56),
                _ToolActionTile(
                  icon: Icons.keyboard_arrow_down_rounded,
                  title: '立即隐藏工具栏',
                  onTap: widget.onHideToolbar,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class RemoteNetworkStatusSheet extends StatefulWidget {
  const RemoteNetworkStatusSheet({super.key});

  @override
  State<RemoteNetworkStatusSheet> createState() =>
      _RemoteNetworkStatusSheetState();
}

class _RemoteNetworkStatusSheetState extends State<RemoteNetworkStatusSheet> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SessionProvider>();
    final session = provider.currentSession;
    final latency = session?.latencyMs;
    final connectedAt = session?.connectedAt;
    final duration = connectedAt == null
        ? '暂无'
        : _formatDuration(DateTime.now().difference(connectedAt));
    final quality = switch (provider.qualityPreset) {
      'low' => '流畅',
      'medium' => '均衡',
      'high' => '高清',
      _ => '自动',
    };

    return _ToolSheet(
      title: '网络状态',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: _ToolCard(
          children: [
            _MetricTile(
              icon: Icons.signal_cellular_alt_rounded,
              label: '会话状态',
              value: provider.connectionStatusLabel,
              accent: provider.isRemoteOnline,
            ),
            const Divider(height: 1, indent: 56),
            _MetricTile(
              icon: Icons.speed_rounded,
              label: '画面延迟',
              value: latency == null ? '暂无' : '$latency ms',
            ),
            const Divider(height: 1, indent: 56),
            _MetricTile(
              icon: Icons.slow_motion_video_rounded,
              label: '帧率上限',
              value: '${provider.fpsLimit} FPS',
            ),
            const Divider(height: 1, indent: 56),
            _MetricTile(
              icon: Icons.hd_outlined,
              label: '当前画质',
              value: quality,
            ),
            const Divider(height: 1, indent: 56),
            _MetricTile(
              icon: Icons.timer_outlined,
              label: '连接时长',
              value: duration,
            ),
            const Divider(height: 1, indent: 56),
            _MetricTile(
              icon: Icons.devices_outlined,
              label: '远端系统',
              value: session?.peerOs.trim().isNotEmpty == true
                  ? session!.peerOs
                  : '未知',
            ),
            const Divider(height: 1, indent: 56),
            _MetricTile(
              icon: Icons.monitor_outlined,
              label: '显示器',
              value:
                  '${provider.currentMonitor + 1} / ${provider.availableMonitors.length}',
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(Duration value) {
    final safeSeconds = value.isNegative ? 0 : value.inSeconds;
    final hours = safeSeconds ~/ 3600;
    final minutes = (safeSeconds % 3600) ~/ 60;
    final seconds = safeSeconds % 60;
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(hours)}:${two(minutes)}:${two(seconds)}';
  }
}

class _ToolSheet extends StatelessWidget {
  const _ToolSheet({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    return Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.68),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon:
                        const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ],
              ),
            ),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

class _ToolSectionLabel extends StatelessWidget {
  const _ToolSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.white.withValues(alpha: 0.55),
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.wide = false,
    this.semanticsLabel,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool wide;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      enabled: enabled,
      child: SizedBox(
        width: wide ? 112 : 68,
        height: 48,
        child: FilledButton.tonal(
          onPressed: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  onTap();
                }
              : null,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            backgroundColor: Colors.white.withValues(alpha: 0.11),
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.white.withValues(alpha: 0.05),
            disabledForegroundColor: Colors.white.withValues(alpha: 0.28),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.white.withValues(alpha: 0.07),
          listTileTheme: const ListTileThemeData(
            textColor: Colors.white,
            iconColor: Colors.white70,
          ),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

class _ToolActionTile extends StatelessWidget {
  const _ToolActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading:
          Icon(icon, color: accent ? AppTheme.successGreen : Colors.white70),
      title: Text(label),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: TextStyle(
            color: accent ? AppTheme.successGreen : Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
