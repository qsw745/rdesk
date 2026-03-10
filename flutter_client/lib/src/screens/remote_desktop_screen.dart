import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/remote_canvas.dart';
import '../widgets/toolbar.dart';

class RemoteDesktopScreen extends StatefulWidget {
  final String sessionId;

  const RemoteDesktopScreen({super.key, required this.sessionId});

  @override
  State<RemoteDesktopScreen> createState() => _RemoteDesktopScreenState();
}

class _RemoteDesktopScreenState extends State<RemoteDesktopScreen> {
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
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;
    final bottomPadding = mediaQuery.padding.bottom;
    final screenWidth = mediaQuery.size.width;

    return Scaffold(
      body: Stack(
        children: [
          // Remote canvas — full screen
          Positioned.fill(
            child: GestureDetector(
              onDoubleTap: () => setState(() => _showToolbar = !_showToolbar),
              child: RemoteCanvas(
                sessionId: widget.sessionId,
                onRemoteTap: (normalizedPosition) async {
                  HapticFeedback.lightImpact();
                  await context.read<SessionProvider>().sendNormalizedTap(
                        widget.sessionId,
                        normalizedPosition,
                      );
                },
                onRemoteLongPress: (normalizedPosition) async {
                  HapticFeedback.mediumImpact();
                  await context
                      .read<SessionProvider>()
                      .sendNormalizedLongPress(
                        widget.sessionId,
                        normalizedPosition,
                      );
                },
                onRemoteDrag: (start, end) async {
                  HapticFeedback.lightImpact();
                  await context.read<SessionProvider>().sendNormalizedDrag(
                        widget.sessionId,
                        start,
                        end,
                      );
                },
              ),
            ),
          ),

          // Connection quality indicator (top-left)
          Positioned(
            top: topPadding + 12,
            left: 18,
            child: IgnorePointer(
              child: _ConnectionQualityBadge(sessionId: widget.sessionId),
            ),
          ),

          // Toolbar
          if (_showToolbar)
            Positioned(
              top: topPadding + 44,
              left: 12,
              right: 12,
              child: Center(
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: screenWidth * 0.95),
                  child: RemoteToolbar(
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
                    onFileManager: () =>
                        context.go('/files/${widget.sessionId}'),
                    onChat: () => context.go('/chat/${widget.sessionId}'),
                    onToggleToolbar: () =>
                        setState(() => _showToolbar = false),
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
                      '双击隐藏工具栏。单击发送点击，长按发送长按，拖动会回传拖拽手势到远程端。',
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

  void _handleRemoteTermination(String connectionStatusLabel) {
    if (_handledRemoteTermination || connectionStatusLabel != '已被对端断开') {
      return;
    }
    _handledRemoteTermination = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SessionProvider>().clearSession();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('远程连接已被对端主动断开'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.go('/');
    });
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
        ({int latency, bool online, bool reconnecting, String label})>(
      selector: (_, p) => (
        latency: p.currentSession?.latencyMs ?? 42,
        online: p.isRemoteOnline,
        reconnecting: p.isReconnecting,
        label: p.connectionStatusLabel,
      ),
      builder: (context, state, _) {
        final color = !state.online
            ? (state.reconnecting ? Colors.amberAccent : Colors.redAccent)
            : state.latency < 50
                ? Colors.greenAccent
                : state.latency < 150
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
                state.online
                    ? '连接质量 ${state.latency}ms'
                    : state.label,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        );
      },
    );
  }
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
        if (state.latency == null) return const SizedBox.shrink();

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
                color:
                    state.reconnecting ? Colors.amber : Colors.redAccent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
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
                latency < 50
                    ? Icons.network_wifi_3_bar
                    : latency < 150
                        ? Icons.network_wifi_2_bar
                        : Icons.network_wifi_1_bar,
                color: latency < 50
                    ? Colors.green
                    : latency < 150
                        ? Colors.amber
                        : Colors.red,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                '延迟 ${latency}ms',
                style: TextStyle(
                  color: latency < 50
                      ? Colors.green
                      : latency < 150
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
