import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/key_mapping.dart';
import '../providers/connection_provider.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/desktop_viewer_sidebar.dart';
import '../widgets/desktop_viewer_top_bar.dart';
import '../widgets/hardware_keyboard_forwarder.dart';
import '../widgets/remote_canvas.dart';
import '../widgets/remote_file_drop.dart';

/// Desktop layout for the remote viewer: TopBar + Canvas + Sidebar.
///
/// The sidebar is toggled via the "控制中心" button in the top bar and
/// animates open/closed with a smooth width transition.
class DesktopViewerLayout extends StatefulWidget {
  final String sessionId;

  const DesktopViewerLayout({super.key, required this.sessionId});

  @override
  State<DesktopViewerLayout> createState() => _DesktopViewerLayoutState();
}

class _DesktopViewerLayoutState extends State<DesktopViewerLayout> {
  bool _sidebarOpen = true;

  // The wheel scrolls the remote computer, in steps: every wheel event as
  // its own request would flood a slow link and keep scrolling long after
  // the wheel stopped.
  static const _scrollStep = Duration(milliseconds: 90);
  DateTime _lastScrollAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    final now = DateTime.now();
    if (now.difference(_lastScrollAt) < _scrollStep) return;
    _lastScrollAt = now;
    context.read<SessionProvider>().sendAction(widget.sessionId,
        event.scrollDelta.dy < 0 ? 'scroll_up' : 'scroll_down');
  }

  @override
  Widget build(BuildContext context) {
    final viewOnly = context.select<SessionProvider, bool>((p) => p.viewOnly);
    final peerOs = context.select<SessionProvider, String>(
        (p) => p.currentSession?.peerOs ?? '');
    return Scaffold(
      body: Column(
        children: [
          // Top bar
          DesktopViewerTopBar(
            sessionId: widget.sessionId,
            isSidebarOpen: _sidebarOpen,
            onToggleSidebar: () =>
                setState(() => _sidebarOpen = !_sidebarOpen),
          ),

          // Main content: canvas + sidebar
          Expanded(
            child: Row(
              children: [
                // Remote canvas — fills remaining space
                Expanded(
                  child: RemoteFileDrop(
                    sessionId: widget.sessionId,
                    child: HardwareKeyboardForwarder(
                      peerOs: peerOs,
                      enabled: !viewOnly,
                      mapping:
                          context.select<SettingsProvider, WindowsKeyMapping>(
                              (settings) => settings.windowsKeyMapping),
                      onText: (text) => context
                          .read<SessionProvider>()
                          .sendTextInput(widget.sessionId, text),
                      onAction: (action) => context
                          .read<SessionProvider>()
                          .sendAction(widget.sessionId, action),
                      child: Listener(
                        onPointerSignal: _onPointerSignal,
                        child: RemoteCanvas(
                          sessionId: widget.sessionId,
                          onRemoteTap: (normalizedPosition) async {
                            await context
                                .read<SessionProvider>()
                                .sendNormalizedTap(
                                  widget.sessionId,
                                  normalizedPosition,
                                );
                          },
                          onRemoteLongPress: (normalizedPosition) async {
                            await context
                                .read<SessionProvider>()
                                .sendNormalizedLongPress(
                                  widget.sessionId,
                                  normalizedPosition,
                                );
                          },
                          onRemoteDrag: (start, end) async {
                            await context
                                .read<SessionProvider>()
                                .sendNormalizedDrag(
                                  widget.sessionId,
                                  start,
                                  end,
                                );
                          },
                          onRemoteDragPath: (points) async {
                            final session = context.read<SessionProvider>();
                            final ok = await session.sendNormalizedDragPath(
                                widget.sessionId, points);
                            // Older desktop hosts only know a start-to-end drag.
                            if (!ok && points.length >= 2) {
                              await session.sendNormalizedDrag(
                                  widget.sessionId, points.first, points.last);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ),

                // Animated sidebar
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  width: _sidebarOpen ? 280 : 0,
                  child: _sidebarOpen
                      ? DesktopViewerSidebar(
                          sessionId: widget.sessionId,
                          onDisconnect: () => _disconnect(context),
                          onFileManager: () =>
                              context.go('/files/${widget.sessionId}'),
                          onRemoteAction: (action) async {
                            HapticFeedback.selectionClick();
                            await context
                                .read<SessionProvider>()
                                .sendAction(widget.sessionId, action);
                          },
                          onRemoteTextInput: () =>
                              _showTextInputDialog(context),
                          onPushClipboard: () => _pushClipboard(context),
                          onPullClipboard: () => _pullClipboard(context),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _disconnect(BuildContext context) {
    context.read<ConnectionProvider>().disconnect(widget.sessionId);
    context.read<SessionProvider>().clearSession();
    context.go('/');
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
    final text = await context
        .read<SessionProvider>()
        .fetchClipboard(widget.sessionId);
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
}
