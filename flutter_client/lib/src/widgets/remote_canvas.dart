import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';

class RemoteCanvas extends StatefulWidget {
  final String sessionId;
  final Future<void> Function(Offset normalizedPosition)? onRemoteTap;
  final Future<void> Function(Offset normalizedPosition)? onRemoteLongPress;
  final Future<void> Function(Offset normalizedStart, Offset normalizedEnd)?
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

  /// Compute DPI-aware drag threshold so the gesture feels consistent across
  /// screens of different pixel densities.
  double _dragThreshold(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio.clamp(1.0, 3.0);
    return 18.0 * dpr / 2.0; // ~9-27 logical pixels
  }

  @override
  Widget build(BuildContext context) {
    return Selector<SessionProvider, bool>(
      selector: (_, p) => p.currentFrame != null && p.currentFrame!.isNotEmpty,
      builder: (context, hasFrame, _) {
        if (!hasFrame) {
          return _buildPlaceholder(context);
        }
        return _buildCanvas(context);
      },
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    final provider = context.watch<SessionProvider>();
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF0F172A),
            Color(0xFF111827),
            Color(0xFF020617),
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

  Widget _buildCanvas(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        final provider = context.read<SessionProvider>();
        final frameSize = Size(
          provider.frameWidth > 0 ? provider.frameWidth.toDouble() : 1,
          provider.frameHeight > 0 ? provider.frameHeight.toDouble() : 1,
        );
        final contentRect = _calculateContainRect(viewportSize, frameSize);
        final threshold = _dragThreshold(context);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: widget.onRemoteTap == null
              ? null
              : (details) {
                  final normalized = _normalizeToContentRect(
                    details.localPosition,
                    contentRect,
                  );
                  if (normalized == null) return;
                  widget.onRemoteTap!(normalized);
                },
          onLongPressStart: widget.onRemoteLongPress == null
              ? null
              : (details) {
                  final normalized = _normalizeToContentRect(
                    details.localPosition,
                    contentRect,
                  );
                  if (normalized == null) return;
                  widget.onRemoteLongPress!(normalized);
                },
          onPanStart: widget.onRemoteDrag == null
              ? null
              : (details) {
                  final normalized = _normalizeToContentRect(
                    details.localPosition,
                    contentRect,
                  );
                  if (normalized == null) {
                    _dragStart = null;
                    _dragCurrent = null;
                    return;
                  }
                  setState(() {
                    _dragStart = _positionInContentRect(
                      normalized,
                      contentRect,
                    );
                    _dragCurrent = _dragStart;
                  });
                },
          onPanUpdate: widget.onRemoteDrag == null
              ? null
              : (details) {
                  if (_dragStart == null) return;
                  setState(() {
                    _dragCurrent = _clampToContentRect(
                      details.localPosition,
                      contentRect,
                    );
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
                  if (start == null || end == null) return;
                  if ((end - start).distance < threshold) return;
                  final normalizedStart =
                      _normalizeToContentRect(start, contentRect);
                  final normalizedEnd =
                      _normalizeToContentRect(end, contentRect);
                  if (normalizedStart == null || normalizedEnd == null) return;
                  widget.onRemoteDrag!(normalizedStart, normalizedEnd);
                },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Frame layer — isolated with RepaintBoundary for performance
              ColoredBox(
                color: Colors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fromRect(
                      rect: contentRect,
                      child: RepaintBoundary(
                        child: _FrameImage(sessionId: widget.sessionId),
                      ),
                    ),
                  ],
                ),
              ),
              // Resolution overlay — uses Selector to avoid rebuilds on every frame
              Positioned(
                top: contentRect.top + 12,
                right: 18,
                child: IgnorePointer(
                  ignoring: true,
                  child: _ResolutionBadge(),
                ),
              ),
              // Offline status overlay
              _OfflineOverlay(),
              // Drag indicator
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
  }

  Rect _calculateContainRect(Size viewportSize, Size imageSize) {
    if (viewportSize.width <= 0 ||
        viewportSize.height <= 0 ||
        imageSize.width <= 0 ||
        imageSize.height <= 0) {
      return Offset.zero & viewportSize;
    }
    final viewportRatio = viewportSize.width / viewportSize.height;
    final imageRatio = imageSize.width / imageSize.height;

    if (imageRatio > viewportRatio) {
      final width = viewportSize.width;
      final height = width / imageRatio;
      final top = (viewportSize.height - height) / 2;
      return Rect.fromLTWH(0, top, width, height);
    }

    final height = viewportSize.height;
    final width = height * imageRatio;
    final left = (viewportSize.width - width) / 2;
    return Rect.fromLTWH(left, 0, width, height);
  }

  Offset? _normalizeToContentRect(Offset position, Rect contentRect) {
    if (!contentRect.contains(position)) return null;
    return Offset(
      ((position.dx - contentRect.left) / contentRect.width).clamp(0.0, 1.0),
      ((position.dy - contentRect.top) / contentRect.height).clamp(0.0, 1.0),
    );
  }

  Offset _positionInContentRect(Offset normalized, Rect contentRect) {
    return Offset(
      contentRect.left + normalized.dx.clamp(0.0, 1.0) * contentRect.width,
      contentRect.top + normalized.dy.clamp(0.0, 1.0) * contentRect.height,
    );
  }

  Offset _clampToContentRect(Offset position, Rect contentRect) {
    return Offset(
      position.dx.clamp(contentRect.left, contentRect.right),
      position.dy.clamp(contentRect.top, contentRect.bottom),
    );
  }
}

/// Isolated frame display widget — only rebuilds when the actual frame bytes
/// change, not when overlay state (latency, connection status) changes.
class _FrameImage extends StatelessWidget {
  final String sessionId;

  const _FrameImage({required this.sessionId});

  @override
  Widget build(BuildContext context) {
    return Selector<SessionProvider, Uint8List?>(
      selector: (_, p) => p.currentFrame,
      builder: (context, frame, _) {
        if (frame == null || frame.isEmpty) {
          return const SizedBox.shrink();
        }
        return ClipRect(
          child: Image.memory(
            frame,
            fit: BoxFit.fill,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
          ),
        );
      },
    );
  }
}

/// Resolution badge — only rebuilds when width/height change.
class _ResolutionBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Selector<SessionProvider, ({int w, int h})>(
      selector: (_, p) => (w: p.frameWidth, h: p.frameHeight),
      builder: (context, dims, _) {
        if (dims.w <= 0 || dims.h <= 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${dims.w} × ${dims.h}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      },
    );
  }
}

/// Offline/reconnecting overlay — only rebuilds when online/reconnecting state changes.
class _OfflineOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Selector<SessionProvider,
        ({bool online, bool reconnecting, String label})>(
      selector: (_, p) => (
        online: p.isRemoteOnline,
        reconnecting: p.isReconnecting,
        label: p.connectionStatusLabel,
      ),
      builder: (context, state, _) {
        if (state.online) return const SizedBox.shrink();
        return Positioned(
          top: 18,
          right: 18,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  if (state.reconnecting)
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
                    state.label,
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
