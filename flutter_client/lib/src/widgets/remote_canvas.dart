import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';

class RemoteCanvas extends StatefulWidget {
  final String sessionId;
  final Future<void> Function(Offset localPosition, Size viewportSize)?
      onRemoteTap;
  final Future<void> Function(Offset localPosition, Size viewportSize)?
      onRemoteLongPress;
  final Future<void> Function(Offset start, Offset end, Size viewportSize)?
      onRemoteDrag;

  const RemoteCanvas({
    super.key,
    required this.sessionId,
    this.onRemoteTap,
    this.onRemoteLongPress,
    this.onRemoteDrag,
  });

  @override
  State<RemoteCanvas> createState() => _RemoteCanvasState();
}

class _RemoteCanvasState extends State<RemoteCanvas> {
  Offset? _dragStart;
  Offset? _dragCurrent;

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionProvider>(
      builder: (context, provider, _) {
        final frame = provider.currentFrame;
        if (frame == null || frame.isEmpty) {
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF0F172A),
                  Color(0xFF111827),
                  Color(0xFF020617)
                ],
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
                  child: const Icon(Icons.desktop_windows,
                      color: Colors.white70, size: 54),
                ),
                const SizedBox(height: 12),
                Text(
                  '已连接会话 ${widget.sessionId}',
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const SizedBox(height: 8),
                Text(
                  provider.connectionStatusLabel == '未连接'
                      ? '等待远程画面...'
                      : provider.connectionStatusLabel,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final viewportSize = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: widget.onRemoteTap == null
                  ? null
                  : (details) =>
                      widget.onRemoteTap!(details.localPosition, viewportSize),
              onLongPressStart: widget.onRemoteLongPress == null
                  ? null
                  : (details) => widget.onRemoteLongPress!(
                      details.localPosition, viewportSize),
              onPanStart: widget.onRemoteDrag == null
                  ? null
                  : (details) {
                      setState(() {
                        _dragStart = details.localPosition;
                        _dragCurrent = details.localPosition;
                      });
                    },
              onPanUpdate: widget.onRemoteDrag == null
                  ? null
                  : (details) {
                      setState(() {
                        _dragCurrent = details.localPosition;
                      });
                    },
              onPanCancel: widget.onRemoteDrag == null
                  ? null
                  : () {
                      setState(() {
                        _dragStart = null;
                        _dragCurrent = null;
                      });
                    },
              onPanEnd: widget.onRemoteDrag == null
                  ? null
                  : (_) {
                      final start = _dragStart;
                      final end = _dragCurrent;
                      setState(() {
                        _dragStart = null;
                        _dragCurrent = null;
                      });
                      if (start == null || end == null) {
                        return;
                      }
                      if ((end - start).distance < 18) {
                        return;
                      }
                      widget.onRemoteDrag!(start, end, viewportSize);
                    },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: Image.memory(
                        frame,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                  if (!provider.isRemoteOnline)
                    Positioned(
                      top: 18,
                      right: 18,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (provider.isReconnecting)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.amberAccent,
                                  ),
                                ),
                              )
                            else
                              const Icon(
                                Icons.portable_wifi_off,
                                color: Colors.redAccent,
                                size: 16,
                              ),
                            const SizedBox(width: 8),
                            Text(
                              provider.connectionStatusLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_dragStart != null && _dragCurrent != null)
                    IgnorePointer(
                      child: CustomPaint(
                        painter: _DragPainter(
                          start: _dragStart!,
                          end: _dragCurrent!,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _DragPainter extends CustomPainter {
  final Offset start;
  final Offset end;

  const _DragPainter({
    required this.start,
    required this.end,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFF33D1FF)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final pointPaint = Paint()
      ..color = const Color(0xFF33D1FF)
      ..style = PaintingStyle.fill;

    canvas.drawLine(start, end, linePaint);
    canvas.drawCircle(start, 8, pointPaint);
    canvas.drawCircle(end, 8, pointPaint);
  }

  @override
  bool shouldRepaint(covariant _DragPainter oldDelegate) {
    return oldDelegate.start != start || oldDelegate.end != end;
  }
}
