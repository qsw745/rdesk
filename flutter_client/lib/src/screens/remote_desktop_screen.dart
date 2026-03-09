import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import '../providers/session_provider.dart';
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

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showHint = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onDoubleTap: () => setState(() => _showToolbar = !_showToolbar),
              child: RemoteCanvas(sessionId: widget.sessionId),
            ),
          ),
          Positioned(
            top: topPadding + 12,
            left: 18,
            child: Consumer<SessionProvider>(
              builder: (context, provider, _) {
                final latency = provider.currentSession?.latencyMs ?? 42;
                final color = latency < 50
                    ? Colors.greenAccent
                    : latency < 150
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
                      Text('连接质量 ${latency}ms', style: const TextStyle(color: Colors.white)),
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
                  onDisconnect: () {
                    context.read<ConnectionProvider>().disconnect(widget.sessionId);
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Text(
                    '双击画面可隐藏工具栏。首次接入时请先确认远端已开始推流。',
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
            ),
          ),
        ],
      ),
    );
  }
}
