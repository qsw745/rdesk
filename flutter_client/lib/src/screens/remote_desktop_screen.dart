import 'dart:async';

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
    _syncAutoClipboardSetting(autoClipboardSync);
    final topPadding = MediaQuery.of(context).padding.top;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onDoubleTap: () => setState(() => _showToolbar = !_showToolbar),
              child: RemoteCanvas(
                sessionId: widget.sessionId,
                onRemoteTap: (localPosition, viewportSize) async {
                  final ok = await context.read<SessionProvider>().sendTap(
                        widget.sessionId,
                        localPosition,
                        viewportSize,
                      );
                  if (!ok || !context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已发送远程点击'),
                      duration: Duration(milliseconds: 800),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                onRemoteLongPress: (localPosition, viewportSize) async {
                  final ok =
                      await context.read<SessionProvider>().sendLongPress(
                            widget.sessionId,
                            localPosition,
                            viewportSize,
                          );
                  if (!ok || !context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已发送远程长按'),
                      duration: Duration(milliseconds: 900),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                onRemoteDrag: (start, end, viewportSize) async {
                  final ok = await context.read<SessionProvider>().sendDrag(
                        widget.sessionId,
                        start,
                        end,
                        viewportSize,
                      );
                  if (!ok || !context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已发送远程拖拽'),
                      duration: Duration(milliseconds: 900),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            top: topPadding + 12,
            left: 18,
            child: Consumer<SessionProvider>(
              builder: (context, provider, _) {
                final latency = provider.currentSession?.latencyMs ?? 42;
                final color = !provider.isRemoteOnline
                    ? (provider.isReconnecting
                        ? Colors.amberAccent
                        : Colors.redAccent)
                    : latency < 50
                        ? Colors.greenAccent
                        : latency < 150
                            ? Colors.amberAccent
                            : Colors.redAccent;
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                        provider.isRemoteOnline
                            ? '连接质量 ${latency}ms'
                            : provider.connectionStatusLabel,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (_showToolbar)
            Positioned(
              top: topPadding + 6,
              left: 0,
              right: 0,
              child: Center(
                child: RemoteToolbar(
                  sessionId: widget.sessionId,
                  onRemoteTextInput: () => _showTextInputDialog(context),
                  onPushClipboard: () => _pushClipboard(context),
                  onPullClipboard: () => _pullClipboard(context),
                  onRemoteAction: (action) async {
                    final ok = await context.read<SessionProvider>().sendAction(
                          widget.sessionId,
                          action,
                        );
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(ok ? '已发送动作 $action' : '动作 $action 未执行'),
                        duration: const Duration(milliseconds: 900),
                        behavior: SnackBarBehavior.floating,
                      ),
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
                  onChat: () => context.go('/chat/${widget.sessionId}'),
                  onToggleToolbar: () => setState(() => _showToolbar = false),
                ),
              ),
            ),
          if (_showHint)
            Positioned(
              left: 20,
              right: 20,
              bottom: 90,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Text(
                    '双击隐藏工具栏。单击发送点击，长按发送长按，拖动会回传拖拽手势到 Android 端。',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: 16,
            right: 16,
            child: Consumer<SessionProvider>(
              builder: (context, provider, _) {
                final latency = provider.currentSession?.latencyMs;
                if (latency == null) return const SizedBox.shrink();
                if (!provider.isRemoteOnline) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      provider.connectionStatusLabel,
                      style: TextStyle(
                        color: provider.isReconnecting
                            ? Colors.amber
                            : Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pushClipboard(BuildContext context) async {
    final local = await Clipboard.getData('text/plain');
    final text = local?.text;
    if (!context.mounted || text == null || text.isEmpty) {
      return;
    }
    final ok = await context.read<SessionProvider>().sendClipboard(
          widget.sessionId,
          text,
        );
    if (!context.mounted) {
      return;
    }
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
    if (!context.mounted || text == null || text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) {
      return;
    }
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
        title: const Text('发送文本到 Android'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '文本内容',
            hintText: '会写入当前聚焦的 Android 输入框',
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

    if (!context.mounted || submitted == null || submitted.isEmpty) {
      return;
    }

    final ok = await context.read<SessionProvider>().sendTextInput(
          widget.sessionId,
          submitted,
        );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '已发送文本' : '文本未写入'),
        duration: const Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _syncAutoClipboardSetting(bool enabled) {
    if (_lastAutoClipboardSync == enabled) {
      return;
    }
    _lastAutoClipboardSync = enabled;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        context.read<SessionProvider>().configureAutoClipboardSync(
              sessionId: widget.sessionId,
              enabled: enabled,
            ),
      );
    });
  }
}
