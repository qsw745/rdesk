import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/platform_util.dart';
import '../widgets/desktop_viewer_layout.dart';
import '../widgets/remote_canvas.dart';
import '../widgets/remote_control_panel.dart';

class RemoteDesktopScreen extends StatefulWidget {
  final String sessionId;

  const RemoteDesktopScreen({super.key, required this.sessionId});

  @override
  State<RemoteDesktopScreen> createState() => _RemoteDesktopScreenState();
}

class _RemoteDesktopScreenState extends State<RemoteDesktopScreen> {
  static const _mobileOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  );

  bool _showToolbar = true;
  bool _showHint = true;
  bool? _lastAutoClipboardSync;
  bool _handledRemoteTermination = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showHint = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final autoClipboardSync = context.select<SettingsProvider, bool>(
      (provider) => provider.autoClipboardSync,
    );
    final connectionStatusLabel = context.select<SessionProvider, String>(
      (provider) => provider.connectionStatusLabel,
    );
    _syncAutoClipboardSetting(autoClipboardSync);
    _handleRemoteTermination(connectionStatusLabel);

    // Desktop: use the UU远程-style layout with top bar + sidebar
    if (PlatformUtil.isDesktop) {
      return DesktopViewerLayout(sessionId: widget.sessionId);
    }

    // Mobile: existing stack-based layout
    return _buildMobileLayout(context);
  }

  Widget _buildMobileLayout(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;
    final bottomPadding = mediaQuery.padding.bottom;
    final screenWidth = mediaQuery.size.width;
    // 仅观看时连震动反馈都不给：输入已在 provider 层丢弃，
    // 再震一下会让人以为点出去了。
    final viewOnly = context.select<SessionProvider, bool>((p) => p.viewOnly);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _mobileOverlayStyle,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Remote canvas — pinch-to-zoom enabled.
            // No outer onDoubleTap wrapper — it delays single-tap recognition
            // by 300ms. Use the floating toggle button below instead.
            //
            // 底栏展开时画布向上内缩相同高度：底栏是半透明浮层，若让画布铺满，
            // 被盖住的正是安卓被控端底部的导航栏区域，点不到也看不见。
            Positioned.fill(
              bottom: _showToolbar ? RemoteControlBar.heightFor(context) : 0,
              child: RemoteCanvas(
                sessionId: widget.sessionId,
                enableZoom: true,
                onRemoteTap: (normalizedPosition) async {
                  if (viewOnly) return;
                  HapticFeedback.lightImpact();
                  await context.read<SessionProvider>().sendNormalizedTap(
                        widget.sessionId,
                        normalizedPosition,
                      );
                },
                onRemoteLongPress: (normalizedPosition) async {
                  if (viewOnly) return;
                  HapticFeedback.mediumImpact();
                  await context.read<SessionProvider>().sendNormalizedLongPress(
                        widget.sessionId,
                        normalizedPosition,
                      );
                },
                onRemoteDrag: (start, end) async {
                  if (viewOnly) return;
                  HapticFeedback.selectionClick();
                  await context.read<SessionProvider>().sendNormalizedDrag(
                        widget.sessionId,
                        start,
                        end,
                      );
                },
                onRemoteDragPath: (points) async {
                  if (viewOnly) return;
                  HapticFeedback.selectionClick();
                  await context.read<SessionProvider>().sendNormalizedDragPath(
                        widget.sessionId,
                        points,
                      );
                },
              ),
            ),

            // Connection quality indicator (top-left) + 当前生效的观看端模式
            Positioned(
              top: topPadding + 12,
              left: 18,
              child: IgnorePointer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ConnectionQualityBadge(sessionId: widget.sessionId),
                    const SizedBox(height: 8),
                    const _ViewerModeBadges(),
                  ],
                ),
              ),
            ),

            // 底部控制栏：高频动作常驻，其余收进「操作」面板
            if (_showToolbar)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: RemoteControlBar(
                  sessionId: widget.sessionId,
                  onRemoteTextInput: () => _showTextInputDialog(context),
                  onPushClipboard: () => _pushClipboard(context),
                  onPullClipboard: () => _pullClipboard(context),
                  onRemoteAction: (action) async {
                    HapticFeedback.selectionClick();
                    await context.read<SessionProvider>().sendAction(
                          widget.sessionId,
                          action,
                        );
                  },
                  onDisconnect: () {
                    context
                        .read<ConnectionProvider>()
                        .disconnect(widget.sessionId);
                    context.read<SessionProvider>().clearSession();
                    context.go('/');
                  },
                  onFileManager: () => context.go('/files/${widget.sessionId}'),
                  onToggleToolbar: () => setState(() => _showToolbar = false),
                ),
              ),

            // Toolbar toggle button — always visible, replaces the old
            // onDoubleTap which delayed single-tap recognition by 300ms.
            if (!_showToolbar)
              Positioned(
                top: topPadding + 12,
                right: 12,
                child: GestureDetector(
                  onTap: () => setState(() => _showToolbar = true),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(
                      Icons.tune,
                      color: Colors.white70,
                      size: 22,
                    ),
                  ),
                ),
              ),

            // First-use hint
            if (_showHint)
              Positioned(
                left: 20,
                right: 20,
                bottom: 90,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: math.min(screenWidth - 40, 400),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Text(
                        '单击发送点击，长按发送长按，双指捏合缩放画面。',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ),

            // Bottom-right latency indicator
            Positioned(
              bottom: bottomPadding + 24,
              right: 12,
              child: IgnorePointer(
                child: _LatencyBadge(sessionId: widget.sessionId),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pushClipboard(BuildContext context) async {
    final local = await Clipboard.getData('text/plain');
    final text = local?.text;
    if (!context.mounted || text == null || text.isEmpty) return;
    final ok = await context.read<SessionProvider>().sendClipboard(
          widget.sessionId,
          text,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '已推送本地剪贴板' : '剪贴板推送失败'),
        duration: const Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pullClipboard(BuildContext context) async {
    final text =
        await context.read<SessionProvider>().fetchClipboard(widget.sessionId);
    if (!context.mounted || text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已拉取远端剪贴板到本机'),
        duration: Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showTextInputDialog(BuildContext context) async {
    final controller = TextEditingController();
    final submitted = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发送文本到远程端'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '文本内容',
            hintText: '会写入当前聚焦的远程输入框',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('发送'),
          ),
        ],
      ),
    );

    if (!context.mounted || submitted == null || submitted.isEmpty) return;

    final ok = await context.read<SessionProvider>().sendTextInput(
          widget.sessionId,
          submitted,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '已发送文本' : '文本未写入'),
        duration: const Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _syncAutoClipboardSetting(bool enabled) {
    if (_lastAutoClipboardSync == enabled) return;
    _lastAutoClipboardSync = enabled;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        context.read<SessionProvider>().configureAutoClipboardSync(
              sessionId: widget.sessionId,
              enabled: enabled,
            ),
      );
    });
  }

  /// 会直接结束会话并退回设备列表的状态。
  ///
  /// 这些都是**重连尝试后确认失败**的结果。此前「已离线」也在其中，但它只是
  /// 本地「多久没收到帧」的超时产物——在重连还没来得及尝试之前就把用户踢走了，
  /// 表现为空闲一会儿或切回前台就退回设备列表。
  /// 现改为让重连流程先跑，真失败时自然会落到「重连失败」或「设备离线」。
  static const _terminalStates = {
    '已被对端断开',
    '设备离线',
    '密码已变更',
    '重连失败',
  };

  void _handleRemoteTermination(String connectionStatusLabel) {
    if (_handledRemoteTermination) return;
    if (!_terminalStates.contains(connectionStatusLabel)) return;

    final isImmediate =
        connectionStatusLabel == '已被对端断开' || connectionStatusLabel == '密码已变更';

    _handledRemoteTermination = true;
    final delay = isImmediate ? Duration.zero : const Duration(seconds: 3);

    Future<void>.delayed(delay, () {
      if (!mounted) return;
      context.read<SessionProvider>().clearSession();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('远程连接已断开：$connectionStatusLabel'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.go('/');
    });
  }
}

/// 观看端模式指示：仅观看 / 指针模式 / 画面旋转。
///
/// 这些开关只改本机行为，不会在远端留下任何痕迹，所以必须在画面上明示，
/// 否则「点了没反应」会被当成连接故障。
class _ViewerModeBadges extends StatelessWidget {
  const _ViewerModeBadges();

  @override
  Widget build(BuildContext context) {
    return Selector<SessionProvider,
        ({bool viewOnly, bool pointer, int turns})>(
      selector: (_, p) => (
        viewOnly: p.viewOnly,
        pointer: p.pointerMode,
        turns: p.rotationQuarterTurns,
      ),
      builder: (context, state, _) {
        final badges = <Widget>[
          if (state.viewOnly)
            const _ModePill(icon: Icons.visibility_outlined, label: '仅观看'),
          if (state.pointer)
            const _ModePill(icon: Icons.mouse_outlined, label: '指针'),
          if (state.turns != 0)
            _ModePill(
              icon: Icons.screen_rotation_rounded,
              label: '${state.turns * 90}°',
            ),
        ];
        if (badges.isEmpty) return const SizedBox.shrink();
        return Wrap(spacing: 6, runSpacing: 6, children: badges);
      },
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white70),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Connection quality badge — top-left corner.
/// Uses Selector to only rebuild when latency / online state changes.
class _ConnectionQualityBadge extends StatelessWidget {
  final String sessionId;

  const _ConnectionQualityBadge({required this.sessionId});

  @override
  Widget build(BuildContext context) {
    return Selector<SessionProvider,
        ({int? latency, bool online, bool reconnecting, String label})>(
      selector: (_, p) => (
        latency: p.currentSession?.latencyMs,
        online: p.isRemoteOnline,
        reconnecting: p.isReconnecting,
        label: p.connectionStatusLabel,
      ),
      builder: (context, state, _) {
        final color = !state.online
            ? (state.reconnecting ? Colors.amberAccent : Colors.redAccent)
            : state.latency == null
                ? Colors.white70
                : state.latency! < _LatencyGrade.good
                    ? Colors.greenAccent
                    : state.latency! < _LatencyGrade.fair
                        ? Colors.amberAccent
                        : Colors.redAccent;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.56),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.graphic_eq, color: color, size: 16),
              const SizedBox(width: 8),
              Text(
                state.online ? '连接质量 ${state.latency ?? "--"}ms' : state.label,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 延迟分档阈值。
///
/// 这里的延迟是「画面从被控端采集到显示在本机」的端到端耗时，链路是
/// 采集 → JPEG 编码 → 手机上行 → 中继服务器 → 本机下行 → 解码，而不是一次
/// ping 的往返。原来沿用 50ms / 150ms 的 ping 式分档，在这条链路上几乎永远
/// 是红色，等于没有分档。按实际可用体验重新划线。
class _LatencyGrade {
  /// 低于此值：跟手，操作几乎无感知延迟。
  static const good = 150;

  /// 低于此值：可正常操作，快速滑动能看出拖影。
  static const fair = 400;
}

/// Latency badge — bottom-right corner.
/// Uses Selector for efficient rebuilds.
class _LatencyBadge extends StatelessWidget {
  final String sessionId;

  const _LatencyBadge({required this.sessionId});

  @override
  Widget build(BuildContext context) {
    return Selector<SessionProvider,
        ({int? latency, bool online, bool reconnecting, String label})>(
      selector: (_, p) => (
        latency: p.currentSession?.latencyMs,
        online: p.isRemoteOnline,
        reconnecting: p.isReconnecting,
        label: p.connectionStatusLabel,
      ),
      builder: (context, state, _) {
        if (!state.online) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              state.label,
              style: TextStyle(
                color: state.reconnecting ? Colors.amber : Colors.redAccent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }

        if (state.latency == null) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              '延迟 -- ms',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          );
        }

        final latency = state.latency!;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                latency < _LatencyGrade.good
                    ? Icons.network_wifi_3_bar
                    : latency < _LatencyGrade.fair
                        ? Icons.network_wifi_2_bar
                        : Icons.network_wifi_1_bar,
                color: latency < _LatencyGrade.good
                    ? Colors.green
                    : latency < _LatencyGrade.fair
                        ? Colors.amber
                        : Colors.red,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                '延迟 ${latency}ms',
                style: TextStyle(
                  color: latency < _LatencyGrade.good
                      ? Colors.green
                      : latency < _LatencyGrade.fair
                          ? Colors.yellow
                          : Colors.red,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
