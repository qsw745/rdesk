import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';
import '../utils/theme.dart';

typedef RemoteActionCallback = Future<void> Function(String action);
typedef RemoteTextCallback = Future<void> Function(String text);

class RemoteKeyboardSheet extends StatefulWidget {
  const RemoteKeyboardSheet({
    super.key,
    required this.peerOs,
    required this.onSendText,
    required this.onRemoteAction,
  });

  final String peerOs;
  final RemoteTextCallback onSendText;
  final RemoteActionCallback onRemoteAction;

  @override
  State<RemoteKeyboardSheet> createState() => _RemoteKeyboardSheetState();
}

class _RemoteKeyboardSheetState extends State<RemoteKeyboardSheet> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  int _selectedTab = 1;
  bool _shiftEnabled = false;

  bool get _supportsDesktopKeys => widget.peerOs.toLowerCase().contains('mac');

  bool get _knownAndroid => widget.peerOs.toLowerCase().contains('android');

  @override
  void dispose() {
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final advancedEnabled = _supportsDesktopKeys;
    final mediaQuery = MediaQuery.of(context);
    final heightFactor =
        mediaQuery.orientation == Orientation.portrait ? 0.50 : 0.76;
    return Container(
      height: mediaQuery.size.height * heightFactor,
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: _KeyboardTabBar(
                      selectedIndex: _selectedTab,
                      onSelected: _selectTab,
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _selectedTab == 0
                    ? _buildInputMethod(context)
                    : _buildComputerKeyboard(advancedEnabled),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputMethod(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('input-method'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _textController,
            focusNode: _textFocusNode,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _submitText(),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: '输入远端文字',
              hintText: '支持中文、英文、数字和符号',
              alignLabelWithHint: true,
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _submitText,
            icon: const Icon(Icons.send_rounded),
            label: const Text('发送到远端'),
          ),
          const SizedBox(height: 12),
          Text(
            '文字会直接发送到远端当前输入位置，不会写入剪贴板。',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.50),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComputerKeyboard(bool advancedEnabled) {
    return SingleChildScrollView(
      key: const ValueKey('computer-keyboard'),
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
      child: Column(
        children: [
          _KeyboardRow(
            children: [
              _KeyboardKey(
                label: 'Esc',
                enabled: advancedEnabled,
                onTap: () => widget.onRemoteAction('key_escape'),
              ),
              _KeyboardKey(
                label: 'Tab',
                enabled: advancedEnabled,
                onTap: () => widget.onRemoteAction('key_tab'),
              ),
              _KeyboardKey(
                label: '←',
                enabled: advancedEnabled,
                semanticsLabel: '左方向键',
                onTap: () => widget.onRemoteAction('key_arrow_left'),
              ),
              _KeyboardKey(
                label: '↑',
                enabled: advancedEnabled,
                semanticsLabel: '上方向键',
                onTap: () => widget.onRemoteAction('key_arrow_up'),
              ),
              _KeyboardKey(
                label: '↓',
                enabled: advancedEnabled,
                semanticsLabel: '下方向键',
                onTap: () => widget.onRemoteAction('key_arrow_down'),
              ),
              _KeyboardKey(
                label: '→',
                enabled: advancedEnabled,
                semanticsLabel: '右方向键',
                onTap: () => widget.onRemoteAction('key_arrow_right'),
              ),
              _KeyboardKey(
                label: '删除',
                flex: 2,
                onTap: () => widget.onRemoteAction('delete'),
              ),
            ],
          ),
          const SizedBox(height: 5),
          _textKeyRow('1234567890'),
          const SizedBox(height: 5),
          _textKeyRow('QWERTYUIOP'),
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: _textKeyRow('ASDFGHJKL'),
          ),
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: _textKeyRow('ZXCVBNM'),
          ),
          const SizedBox(height: 5),
          _KeyboardRow(
            children: [
              _KeyboardKey(
                label: 'Shift',
                flex: 2,
                selected: _shiftEnabled,
                onTap: () => setState(() => _shiftEnabled = !_shiftEnabled),
              ),
              _KeyboardKey(
                label: 'Space',
                flex: 4,
                onTap: () => widget.onSendText(' '),
              ),
              _KeyboardKey(
                label: 'Enter',
                flex: 2,
                onTap: () => widget.onRemoteAction('enter'),
              ),
            ],
          ),
          if (advancedEnabled) ...[
            const SizedBox(height: 10),
            const _ToolSectionLabel('macOS 快捷组合'),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _KeyButton(
                    label: '全选',
                    width: 55,
                    semanticsLabel: '全选',
                    onTap: () => widget.onRemoteAction('key_command_a'),
                  ),
                  const SizedBox(width: 7),
                  _KeyButton(
                    label: '复制',
                    width: 55,
                    semanticsLabel: '复制',
                    onTap: () => widget.onRemoteAction('key_command_c'),
                  ),
                  const SizedBox(width: 7),
                  _KeyButton(
                    label: '粘贴',
                    width: 55,
                    semanticsLabel: '粘贴',
                    onTap: () => widget.onRemoteAction('key_command_v'),
                  ),
                  const SizedBox(width: 7),
                  _KeyButton(
                    label: '剪切',
                    width: 55,
                    semanticsLabel: '剪切',
                    onTap: () => widget.onRemoteAction('key_command_x'),
                  ),
                  const SizedBox(width: 7),
                  _KeyButton(
                    label: '撤销',
                    width: 55,
                    semanticsLabel: '撤销',
                    onTap: () => widget.onRemoteAction('key_command_z'),
                  ),
                  const SizedBox(width: 7),
                  _KeyButton(
                    label: '重做',
                    width: 55,
                    semanticsLabel: '重做',
                    onTap: () => widget.onRemoteAction('key_command_shift_z'),
                  ),
                ],
              ),
            ),
          ],
          if (!advancedEnabled) ...[
            const SizedBox(height: 14),
            Text(
              _knownAndroid
                  ? '安卓被控端支持文字、删除和回车；桌面专用按键已停用。'
                  : '确认远端系统前，桌面专用按键保持停用。',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.52),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _textKeyRow(String characters) {
    return _KeyboardRow(
      children: characters.split('').map((character) {
        return _KeyboardKey(
          label: character,
          onTap: () {
            final text = RegExp('[A-Z]').hasMatch(character)
                ? (_shiftEnabled ? character : character.toLowerCase())
                : character;
            widget.onSendText(text);
            if (_shiftEnabled && RegExp('[A-Z]').hasMatch(character)) {
              setState(() => _shiftEnabled = false);
            }
          },
        );
      }).toList(),
    );
  }

  void _selectTab(int index) {
    if (_selectedTab == index) return;
    setState(() => _selectedTab = index);
    if (index == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _textFocusNode.requestFocus();
      });
    }
  }

  void _submitText() {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    widget.onSendText(text);
    _textController.clear();
  }
}

class _KeyboardTabBar extends StatelessWidget {
  const _KeyboardTabBar({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _KeyboardTab(
            label: '输入法',
            selected: selectedIndex == 0,
            onTap: () => onSelected(0),
          ),
          _KeyboardTab(
            label: '电脑键盘',
            selected: selectedIndex == 1,
            onTap: () => onSelected(1),
          ),
        ],
      ),
    );
  }
}

class _KeyboardTab extends StatelessWidget {
  const _KeyboardTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected
            ? Colors.white.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white60,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyboardRow extends StatelessWidget {
  const _KeyboardRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const SizedBox(width: 5),
          children[index],
        ],
      ],
    );
  }
}

class _KeyboardKey extends StatelessWidget {
  const _KeyboardKey({
    required this.label,
    required this.onTap,
    this.flex = 1,
    this.enabled = true,
    this.selected = false,
    this.semanticsLabel,
  });

  final String label;
  final VoidCallback onTap;
  final int flex;
  final bool enabled;
  final bool selected;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Semantics(
        button: true,
        label: semanticsLabel,
        enabled: enabled,
        selected: selected,
        child: SizedBox(
          height: 38,
          child: FilledButton(
            onPressed: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    onTap();
                  }
                : null,
            style: FilledButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor: selected
                  ? AppTheme.primaryBlue.withValues(alpha: 0.72)
                  : Colors.white.withValues(alpha: 0.12),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.05),
              disabledForegroundColor: Colors.white.withValues(alpha: 0.27),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: selected
                      ? AppTheme.primaryBlue.withValues(alpha: 0.8)
                      : Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
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
    required this.width,
    this.semanticsLabel,
  });

  final String label;
  final VoidCallback onTap;
  final double width;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: SizedBox(
        width: width,
        height: 48,
        child: FilledButton.tonal(
          onPressed: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            backgroundColor: Colors.white.withValues(alpha: 0.11),
            foregroundColor: Colors.white,
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
