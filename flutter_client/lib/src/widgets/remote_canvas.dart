import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';

class RemoteCanvas extends StatelessWidget {
  final String sessionId;

  const RemoteCanvas({
    super.key,
    required this.sessionId,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionProvider>(
      builder: (context, provider, _) {
        final frame = provider.currentFrame;
        if (frame == null || frame.isEmpty) {
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF111827), Color(0xFF020617)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.desktop_windows, color: Colors.white70, size: 54),
                ),
                const SizedBox(height: 12),
                Text(
                  '已连接会话 $sessionId',
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const SizedBox(height: 8),
                const Text(
                  '等待远程画面...',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          );
        }

        return ColoredBox(
          color: Colors.black,
          child: Center(
            child: Image.memory(
              frame,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            ),
          ),
        );
      },
    );
  }
}
