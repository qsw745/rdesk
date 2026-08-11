import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';
import '../utils/theme.dart';
import 'toolbar.dart' show QualitySettingsContent;

/// 远控会话的底部控制栏。
///
/// 取代此前把二十个动作塞进一条横向滚动胶囊条的做法：高频动作常驻底栏，
/// 低频动作收进「操作」面板分组呈现。
class RemoteControlBar extends StatelessWidget {
  const RemoteControlBar({
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

  final String sessionId;
  final VoidCallback onDisconnect;
  final VoidCallback onFileManager;
  final VoidCallback onChat;
  final VoidCallback onToggleToolbar;
  final Future<void> Function(String action) onRemoteAction;
  final Future<void> Function() onRemoteTextInput;
  final Future<void> Function() onPushClipboard;
  final Future<void> Function() onPullClipboard;

  @override
  Widget build(BuildContext context) {
    // 横屏时远程画面本就偏宽，底部横栏会压掉可视高度；改为贴右侧竖排，
    // 与手持横屏时拇指的自然位置也更接近。
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final padding = MediaQuery.of(context).padding;

    final items = <Widget>[
      _BarItem(
        icon: Icons.arrow_back_rounded,
        label: '返回',
        vertical: isLandscape,
        onTap: () => onRemoteAction('back'),
      ),
      _BarItem(
        icon: Icons.home_rounded,
        label: '主页',
        vertical: isLandscape,
        onTap: () => onRemoteAction('home'),
      ),
      _BarItem(
        icon: Icons.grid_view_rounded,
        label: '任务',
        vertical: isLandscape,
        onTap: () => onRemoteAction('recents'),
      ),
      _BarItem(
        icon: Icons.keyboard_alt_outlined,
        label: '键盘',
        vertical: isLandscape,
        onTap: onRemoteTextInput,
      ),
      _BarItem(
        icon: Icons.tune_rounded,
        label: '操作',
        vertical: isLandscape,
        onTap: () => _openActionSheet(context),
      ),
    ];

    final surface = Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        border: Border(
          top: isLandscape
              ? BorderSide.none
              : BorderSide(color: Colors.white.withValues(alpha: 0.10)),
          left: isLandscape
              ? BorderSide(color: Colors.white.withValues(alpha: 0.10))
              : BorderSide.none,
        ),
      ),
      padding: isLandscape
          ? EdgeInsets.only(
              left: 6, right: 6 + padding.right * 0.4, top: 12, bottom: 12)
          : EdgeInsets.only(top: 8, bottom: 8 + padding.bottom * 0.4),
      child: isLandscape
          ? Column(mainAxisSize: MainAxisSize.min, children: items)
          : Row(children: items),
    );

    return ClipRRect(
      borderRadius: isLandscape
          ? const BorderRadius.horizontal(left: Radius.circular(20))
          : const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: surface,
      ),
    );
  }

  void _openActionSheet(BuildContext context) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => RemoteActionSheet(
        sessionId: sessionId,
        onDisconnect: onDisconnect,
        onFileManager: onFileManager,
        onChat: onChat,
        onToggleToolbar: onToggleToolbar,
        onRemoteAction: onRemoteAction,
        onPushClipboard: onPushClipboard,
        onPullClipboard: onPullClipboard,
      ),
    );
  }
}

/// 常驻键盘面板。
///
/// 取代此前"输入 → 发送 → 弹窗关闭 → 再输要重新点开"的一次性对话框：
/// 面板保持打开，可连续输入，删除/回车即点即发。
///
/// 只包含协议真实支持的能力——文本输入、删除、回车、剪贴板。
/// 参考产品里的「电脑键盘」页含修饰键、方向键与功能键，RDesk 的输入协议
/// 目前只有 delete 与 enter 两个键，做出来大部分按键会没有反应，故不实现。
class RemoteKeyboardSheet extends StatefulWidget {
  const RemoteKeyboardSheet({
    super.key,
    required this.onSendText,
    required this.onRemoteAction,
    required this.onPushClipboard,
  });

  final Future<bool> Function(String text) onSendText;
  final Future<void> Function(String action) onRemoteAction;
  final Future<void> Function() onPushClipboard;

  @override
  State<RemoteKeyboardSheet> createState() => _RemoteKeyboardSheetState();
}

class _RemoteKeyboardSheetState extends State<RemoteKeyboardSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (text.isEmpty || _sending) {
      return;
    }
    setState(() => _sending = true);
    final ok = await widget.onSendText(text);
    if (!mounted) {
      return;
    }
    setState(() => _sending = false);
    if (ok) {
      // 发送成功才清空：失败时保留内容，避免用户白打一遍。
      _controller.clear();
      // 保持焦点，面板不关闭，可继续连续输入。
      _focusNode.requestFocus();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('文本未写入，请确认远程端已聚焦输入框'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(milliseconds: 1200),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 顶开系统键盘，输入框不被遮住
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1C1C1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SheetHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        autofocus: true,
                        minLines: 1,
                        maxLines: 4,
                        style: const TextStyle(color: Colors.white),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: '输入后发送到远程端当前输入框',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 14,
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _KeyButton(
                      label: _sending ? '发送中' : '发送',
                      primary: true,
                      onTap: _send,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    _KeyButton(
                      label: '删除',
                      icon: Icons.backspace_outlined,
                      onTap: () => widget.onRemoteAction('delete'),
                    ),
                    const SizedBox(width: 10),
                    _KeyButton(
                      label: '回车',
                      icon: Icons.keyboard_return_rounded,
                      onTap: () => widget.onRemoteAction('enter'),
                    ),
                    const SizedBox(width: 10),
                    _KeyButton(
                      label: '粘贴板',
                      icon: Icons.content_paste_rounded,
                      onTap: widget.onPushClipboard,
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
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final iconData = icon;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: primary
              ? AppTheme.primaryBlue
              : Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (iconData != null) ...[
              Icon(iconData, size: 17, color: Colors.white),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.vertical = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// 竖排（横屏右侧栏）时不使用 [Expanded]——父级是 Column 且高度不受限，
  /// 强行 Expanded 会导致无界高度约束报错。
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: vertical
            ? const EdgeInsets.symmetric(vertical: 10, horizontal: 8)
            : const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: Colors.white),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.white),
            ),
          ],
        ),
      ),
    );

    return vertical ? button : Expanded(child: button);
  }
}

/// 「操作」面板：快捷开关 + 分组入口。
class RemoteActionSheet extends StatelessWidget {
  const RemoteActionSheet({
    super.key,
    required this.sessionId,
    required this.onDisconnect,
    required this.onFileManager,
    required this.onChat,
    required this.onToggleToolbar,
    required this.onRemoteAction,
    required this.onPushClipboard,
    required this.onPullClipboard,
  });

  final String sessionId;
  final VoidCallback onDisconnect;
  final VoidCallback onFileManager;
  final VoidCallback onChat;
  final VoidCallback onToggleToolbar;
  final Future<void> Function(String action) onRemoteAction;
  final Future<void> Function() onPushClipboard;
  final Future<void> Function() onPullClipboard;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final maxHeight = MediaQuery.of(context).size.height * 0.82;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SheetHandle(),
              _QuickChipRow(
                isRecording: session.isRecording,
                privacyScreenOn: session.privacyScreenOn,
                viewOnly: session.viewOnly,
                onDisconnect: () {
                  Navigator.pop(context);
                  onDisconnect();
                },
                onToggleFullscreen: () => _toggleFullscreen(context),
                onTogglePrivacy: () => _togglePrivacyScreen(context),
                onToggleRecording: () => _toggleRecording(context),
                onToggleViewOnly: () => _toggleViewOnly(context),
                onRotate: () => _rotateView(context),
                onHideToolbar: () {
                  Navigator.pop(context);
                  onToggleToolbar();
                },
              ),
              const _SectionLabel('操作'),
              _GroupCard(
                children: [
                  _ScrollRow(onRemoteAction: onRemoteAction),
                  const _GroupDivider(),
                  _ActionRow(
                    icon: Icons.backspace_outlined,
                    title: '删除',
                    onTap: () => onRemoteAction('delete'),
                  ),
                  const _GroupDivider(),
                  _ActionRow(
                    icon: Icons.keyboard_return_rounded,
                    title: '回车',
                    onTap: () => onRemoteAction('enter'),
                  ),
                  const _GroupDivider(),
                  _ActionRow(
                    icon: Icons.power_settings_new_rounded,
                    title: '唤醒屏幕',
                    onTap: () => onRemoteAction('wake'),
                  ),
                ],
              ),
              const _SectionLabel('剪贴板'),
              _GroupCard(
                children: [
                  _ActionRow(
                    icon: Icons.upload_rounded,
                    title: '发送到远端',
                    subtitle: '把本机剪贴板内容推送过去',
                    onTap: () {
                      Navigator.pop(context);
                      onPushClipboard();
                    },
                  ),
                  const _GroupDivider(),
                  _ActionRow(
                    icon: Icons.download_rounded,
                    title: '从远端获取',
                    subtitle: '拉取远端剪贴板到本机',
                    onTap: () {
                      Navigator.pop(context);
                      onPullClipboard();
                    },
                  ),
                ],
              ),
              const _SectionLabel('更多'),
              _GroupCard(
                children: [
                  _ActionRow(
                    icon: Icons.hd_outlined,
                    title: '画质设置',
                    chevron: true,
                    onTap: () => _showQualityDialog(context),
                  ),
                  const _GroupDivider(),
                  _ActionRow(
                    icon: Icons.monitor_outlined,
                    title: '显示器',
                    subtitle: session.availableMonitors.isEmpty
                        ? null
                        : '共 ${session.availableMonitors.length} 个',
                    chevron: true,
                    onTap: () => _showMonitorPicker(context),
                  ),
                  const _GroupDivider(),
                  _ActionRow(
                    icon: Icons.folder_open_rounded,
                    title: '文件传输',
                    chevron: true,
                    onTap: () {
                      Navigator.pop(context);
                      onFileManager();
                    },
                  ),
                  const _GroupDivider(),
                  _ActionRow(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: '会话聊天',
                    chevron: true,
                    onTap: () {
                      Navigator.pop(context);
                      onChat();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleFullscreen(BuildContext context) {
    final isFullscreen = MediaQuery.of(context).padding.top == 0;
    SystemChrome.setEnabledSystemUIMode(
      isFullscreen ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
    _toast(context, isFullscreen ? '已退出全屏' : '已进入全屏模式');
  }

  void _toggleViewOnly(BuildContext context) {
    final session = context.read<SessionProvider>();
    session.toggleViewOnly();
    _toast(context, session.viewOnly ? '已切换为仅观看，不会向对方发送任何操作' : '已恢复远程控制');
  }

  void _rotateView(BuildContext context) {
    final session = context.read<SessionProvider>();
    session.rotateView();
    _toast(context, '画面已旋转 ${session.viewRotationQuarterTurns * 90}°');
  }

  void _togglePrivacyScreen(BuildContext context) {
    final session = context.read<SessionProvider>();
    session.togglePrivacyScreen();
    _toast(context, session.privacyScreenOn ? '隐私屏已开启' : '隐私屏已关闭');
  }

  void _toggleRecording(BuildContext context) {
    final session = context.read<SessionProvider>();
    session.toggleRecording();
    _toast(context, session.isRecording ? '录屏已开始' : '录屏已停止');
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 800),
      ),
    );
  }

  void _showQualityDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SheetShell(child: QualitySettingsContent()),
    );
  }

  void _showMonitorPicker(BuildContext context) {
    final session = context.read<SessionProvider>();
    final monitors = session.availableMonitors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SheetShell(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '选择显示器',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            ...List.generate(monitors.length, (i) {
              final selected = session.currentMonitor == i;
              return ListTile(
                leading: Icon(
                  Icons.monitor_outlined,
                  color: selected ? AppTheme.primaryBlue : Colors.white70,
                ),
                title: Text(
                  monitors[i],
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  '显示器 ${i + 1}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                ),
                trailing: selected
                    ? const Icon(Icons.check_rounded,
                        color: AppTheme.primaryBlue)
                    : null,
                onTap: () {
                  session.setMonitor(i);
                  Navigator.pop(ctx);
                },
              );
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [const _SheetHandle(), child],
        ),
      ),
    );
  }
}

/// 顶部快捷开关行：横向滚动的大圆角按钮，开启态高亮。
class _QuickChipRow extends StatelessWidget {
  const _QuickChipRow({
    required this.isRecording,
    required this.privacyScreenOn,
    required this.viewOnly,
    required this.onDisconnect,
    required this.onToggleFullscreen,
    required this.onTogglePrivacy,
    required this.onToggleRecording,
    required this.onToggleViewOnly,
    required this.onRotate,
    required this.onHideToolbar,
  });

  final bool isRecording;
  final bool privacyScreenOn;
  final bool viewOnly;
  final VoidCallback onDisconnect;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onTogglePrivacy;
  final VoidCallback onToggleRecording;
  final VoidCallback onToggleViewOnly;
  final VoidCallback onRotate;
  final VoidCallback onHideToolbar;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          _Chip(
            icon: Icons.logout_rounded,
            label: '退出远控',
            danger: true,
            onTap: onDisconnect,
          ),
          _Chip(
            icon: Icons.screen_rotation_rounded,
            label: '旋转屏幕',
            onTap: onRotate,
          ),
          _Chip(
            icon: Icons.visibility_rounded,
            label: '仅观看',
            active: viewOnly,
            onTap: onToggleViewOnly,
          ),
          _Chip(
            icon: Icons.fullscreen_rounded,
            label: '全屏',
            onTap: onToggleFullscreen,
          ),
          _Chip(
            icon: Icons.privacy_tip_outlined,
            label: '隐私屏',
            active: privacyScreenOn,
            onTap: onTogglePrivacy,
          ),
          _Chip(
            icon: Icons.fiber_manual_record,
            label: '录屏',
            active: isRecording,
            onTap: onToggleRecording,
          ),
          _Chip(
            icon: Icons.visibility_off_outlined,
            label: '隐藏工具栏',
            onTap: onHideToolbar,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    if (danger) {
      background = const Color(0xFFFF453A).withValues(alpha: 0.18);
      foreground = const Color(0xFFFF6961);
    } else if (active) {
      background = AppTheme.primaryBlue;
      foreground = Colors.white;
    } else {
      background = Colors.white.withValues(alpha: 0.10);
      foreground = Colors.white;
    }

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 96,
          height: 84,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: foreground),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 上滑 / 下滑的分段控件。
class _ScrollRow extends StatelessWidget {
  const _ScrollRow({required this.onRemoteAction});

  final Future<void> Function(String action) onRemoteAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          const Icon(Icons.swap_vert_rounded, size: 20, color: Colors.white70),
          const SizedBox(width: 12),
          const Text('滚动', style: TextStyle(fontSize: 15, color: Colors.white)),
          const Spacer(),
          _SegButton(
            label: '上滑',
            onTap: () => onRemoteAction('scroll_up'),
          ),
          const SizedBox(width: 8),
          _SegButton(
            label: '下滑',
            onTap: () => onRemoteAction('scroll_down'),
          ),
        ],
      ),
    );
  }
}

class _SegButton extends StatelessWidget {
  const _SegButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _GroupDivider extends StatelessWidget {
  const _GroupDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 48,
      color: Colors.white.withValues(alpha: 0.06),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.chevron = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool chevron;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitleText = subtitle;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.white70),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 15, color: Colors.white),
                  ),
                  if (subtitleText != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitleText,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (chevron)
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Colors.white.withValues(alpha: 0.35),
              ),
          ],
        ),
      ),
    );
  }
}
