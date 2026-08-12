import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';
import '../utils/canvas_rotation.dart';
import 'remote_pointer_layer.dart';

class RemoteCanvas extends StatefulWidget {
  final String sessionId;
  final Future<void> Function(Offset normalizedPosition)? onRemoteTap;
  final Future<void> Function(Offset normalizedPosition)? onRemoteLongPress;
  final Future<void> Function(Offset normalizedStart, Offset normalizedEnd)?
      onRemoteDrag;

  /// Called with a list of normalized drag path points for smoother swipes.
  final Future<void> Function(List<Offset> normalizedPoints)? onRemoteDragPath;

  /// Enable pinch-to-zoom (for mobile viewers).
  final bool enableZoom;

  const RemoteCanvas({
    super.key,
    required this.sessionId,
    this.onRemoteTap,
    this.onRemoteLongPress,
    this.onRemoteDrag,
    this.onRemoteDragPath,
    this.enableZoom = false,
  });

  @override
  State<RemoteCanvas> createState() => _RemoteCanvasState();
}

class _RemoteCanvasState extends State<RemoteCanvas> {
  Offset? _dragStart;
  Offset? _dragCurrent;

  /// Collected raw drag path points (in local widget coordinates).
  final List<Offset> _dragPathPoints = [];
  final TransformationController _zoomController = TransformationController();
  bool _isZoomed = false;
  int _activePointers = 0;
  // Raw tap detection via Listener (bypasses gesture arena)
  Offset? _pointerDownPos;
  DateTime? _pointerDownTime;
  bool _pointerMoved = false;

  /// 指针模式下虚拟指针的位置（画面空间归一化坐标）。
  Offset _pointerFramePos = const Offset(0.5, 0.5);

  /// 已武装拖拽：下一次拖动作为拖拽发出，而不是移动指针。
  bool _pointerDragArmed = false;

  /// 武装拖拽期间指针经过的轨迹（画面空间）。
  final List<Offset> _pointerTrail = [];

  /// 按住多久算长按。缩放分支只有 Listener，没有长按识别器，
  /// 这个阈值同时也是「点击 / 长按」的分界。
  static const _longPressThreshold = Duration(milliseconds: 450);

  @override
  void initState() {
    super.initState();
    _zoomController.addListener(_onZoomChanged);
  }

  @override
  void dispose() {
    _zoomController.removeListener(_onZoomChanged);
    _zoomController.dispose();
    super.dispose();
  }

  void _onZoomChanged() {
    final zoomed = _zoomController.value.getMaxScaleOnAxis() > 1.05;
    if (zoomed != _isZoomed) {
      setState(() => _isZoomed = zoomed);
    }
  }

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
    // 旋转与指针模式是观看端行为，直接从 provider 取，避免层层传参。
    final viewState = context.select<SessionProvider, (int, bool)>(
      (p) => (p.rotationQuarterTurns, p.pointerMode),
    );
    final quarterTurns = viewState.$1;
    // 指针模式只在移动端（启用缩放的画布）生效，桌面端本来就有真鼠标。
    final pointerMode = viewState.$2 && widget.enableZoom;

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
        // 旋转奇数档时画面宽高互换，居中矩形必须按旋转后的尺寸算。
        final contentRect = _calculateContainRect(
          viewportSize,
          CanvasRotation.displaySize(frameSize, quarterTurns),
        );
        final threshold = _dragThreshold(context);

        /// 屏幕坐标 → 被控端认的画面空间归一化坐标。
        ///
        /// 先反解缩放矩阵拿到未变换位置，再按旋转档位换算回画面空间。
        Offset? toFrame(Offset screenPos) {
          Offset localPos = screenPos;
          if (widget.enableZoom) {
            // Invert the zoom transform to get the untransformed position.
            final inverse = Matrix4.inverted(_zoomController.value);
            localPos = MatrixUtils.transformPoint(inverse, screenPos);
          }
          final display = _normalizeToContentRect(localPos, contentRect);
          if (display == null) return null;
          return CanvasRotation.displayToFrame(display, quarterTurns);
        }

        final frameLayer = Stack(
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
                      child: RotatedBox(
                        quarterTurns: quarterTurns,
                        child: _FrameImage(sessionId: widget.sessionId),
                      ),
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
          ],
        );

        // When zoom is enabled, use InteractiveViewer for pinch-to-zoom.
        // All single-finger gestures (tap, drag) are detected via
        // InteractiveViewer's own onInteraction* callbacks to avoid
        // gesture arena conflicts.
        if (widget.enableZoom) {
          final interactive = Listener(
            onPointerDown: (event) {
              _activePointers++;
              // Track first finger for tap detection
              if (_activePointers == 1) {
                _pointerDownPos = event.localPosition;
                _pointerDownTime = DateTime.now();
                _pointerMoved = false;
              }
            },
            onPointerMove: (event) {
              // Track movement to distinguish tap from drag
              if (_pointerDownPos != null && !_pointerMoved) {
                final dist = (event.localPosition - _pointerDownPos!).distance;
                if (dist > threshold) {
                  _pointerMoved = true;
                }
              }
            },
            onPointerUp: (event) {
              _activePointers = (_activePointers - 1).clamp(0, 10);

              final downPos = _pointerDownPos;
              final downTime = _pointerDownTime;
              final moved = _pointerMoved;

              if (_activePointers == 0) {
                _pointerDownPos = null;
                _pointerDownTime = null;
                _pointerMoved = false;
              }

              // Single-finger tap / long press: small movement, duration
              // decides which. 此前这里只识别点击，按住再抬手什么都不发——
              // 提示语写着「长按发送长按」，实际在缩放画布上从未生效。
              if (downPos != null && downTime != null && _activePointers == 0) {
                final duration = DateTime.now().difference(downTime);
                debugPrint(
                    '[RDesk] pointerUp: moved=$moved isZoomed=$_isZoomed '
                    'duration=${duration.inMilliseconds}ms pos=$downPos');
                if (moved) return;

                final isLongPress = duration >= _longPressThreshold;
                // 指针模式下落点是虚拟指针的位置，而不是手指位置。
                final target =
                    pointerMode ? _pointerFramePos : toFrame(downPos);
                if (target == null) return;
                debugPrint('[RDesk] ${isLongPress ? "longPress" : "tap"} '
                    'frame=$target');
                if (isLongPress) {
                  widget.onRemoteLongPress?.call(target);
                } else {
                  widget.onRemoteTap?.call(target);
                }
              }
            },
            onPointerCancel: (_) {
              _activePointers = (_activePointers - 1).clamp(0, 10);
              if (_activePointers == 0) {
                _pointerDownPos = null;
                _pointerDownTime = null;
                _pointerMoved = false;
              }
            },
            child: InteractiveViewer(
              transformationController: _zoomController,
              minScale: 1.0,
              maxScale: 5.0,
              // 指针模式下单指用来移动指针，不能同时拖动画面。
              panEnabled: _isZoomed && !pointerMode,
              onInteractionStart: (details) {
                if (pointerMode) {
                  if (details.pointerCount == 1) {
                    _pointerTrail
                      ..clear()
                      ..add(_pointerFramePos);
                  }
                  return;
                }
                if (details.pointerCount == 1 && !_isZoomed) {
                  _dragStart = details.focalPoint;
                  _dragCurrent = _dragStart;
                  _dragPathPoints.clear();
                  _dragPathPoints.add(details.focalPoint);
                } else {
                  _dragStart = null;
                  _dragPathPoints.clear();
                }
              },
              onInteractionUpdate: (details) {
                if (pointerMode) {
                  if (details.pointerCount != 1) return;
                  _movePointer(
                    details.focalPointDelta,
                    contentRect,
                    quarterTurns,
                  );
                  return;
                }
                if (_dragStart != null && details.pointerCount == 1) {
                  _dragCurrent = details.focalPoint;
                  // Sample points but avoid excessive density
                  if (_dragPathPoints.isEmpty ||
                      (details.focalPoint - _dragPathPoints.last).distance >
                          3) {
                    _dragPathPoints.add(details.focalPoint);
                  }
                }
                if (details.pointerCount > 1) {
                  _dragStart = null;
                  _dragPathPoints.clear();
                }
              },
              onInteractionEnd: (details) {
                if (pointerMode) {
                  _flushPointerDrag();
                  return;
                }
                final start = _dragStart;
                final end = _dragCurrent;
                final pathPoints = List<Offset>.from(_dragPathPoints);
                _dragStart = null;
                _dragCurrent = null;
                _dragPathPoints.clear();

                if (start == null || end == null || _isZoomed) return;

                final distance = (end - start).distance;
                if (distance < threshold) return;

                // Prefer path-based drag for smoother swipes
                if (widget.onRemoteDragPath != null && pathPoints.length >= 2) {
                  // Subsample to max ~20 points
                  final sampled = _subsamplePath(pathPoints, 20);
                  final normalizedPath = sampled
                      .map((p) => toFrame(p))
                      .where((p) => p != null)
                      .cast<Offset>()
                      .toList();
                  if (normalizedPath.length >= 2) {
                    widget.onRemoteDragPath!(normalizedPath);
                    return;
                  }
                }
                // Fallback to start/end
                if (widget.onRemoteDrag != null) {
                  final normalizedStart = toFrame(start);
                  final normalizedEnd = toFrame(end);
                  if (normalizedStart != null && normalizedEnd != null) {
                    widget.onRemoteDrag!(normalizedStart, normalizedEnd);
                  }
                }
              },
              child: frameLayer,
            ),
          );

          if (!pointerMode) return interactive;
          return Stack(
            fit: StackFit.expand,
            children: [
              interactive,
              RemotePointerLayer(
                zoom: _zoomController,
                contentRect: contentRect,
                pointerFramePosition: _pointerFramePos,
                quarterTurns: quarterTurns,
                dragArmed: _pointerDragArmed,
                onTap: () => widget.onRemoteTap?.call(_pointerFramePos),
                onLongPress: () =>
                    widget.onRemoteLongPress?.call(_pointerFramePos),
                onToggleDrag: () => setState(
                  () => _pointerDragArmed = !_pointerDragArmed,
                ),
              ),
            ],
          );
        }

        // Non-zoom mode: original gesture handling with tap + drag support.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: widget.onRemoteTap == null
              ? null
              : (details) {
                  final normalized = toFrame(details.localPosition);
                  if (normalized == null) return;
                  debugPrint(
                      '[RDesk] tap at ${normalized.dx.toStringAsFixed(3)}, '
                      '${normalized.dy.toStringAsFixed(3)}');
                  widget.onRemoteTap!(normalized);
                },
          onLongPressStart: widget.onRemoteLongPress == null
              ? null
              : (details) {
                  final normalized = toFrame(details.localPosition);
                  if (normalized == null) return;
                  widget.onRemoteLongPress!(normalized);
                },
          onPanStart:
              (widget.onRemoteDrag == null && widget.onRemoteDragPath == null)
                  ? null
                  : (details) {
                      final normalized = _normalizeToContentRect(
                        details.localPosition,
                        contentRect,
                      );
                      if (normalized == null) {
                        _dragStart = null;
                        _dragCurrent = null;
                        _dragPathPoints.clear();
                        return;
                      }
                      _dragStart = _positionInContentRect(
                        normalized,
                        contentRect,
                      );
                      _dragCurrent = _dragStart;
                      _dragPathPoints.clear();
                      _dragPathPoints.add(details.localPosition);
                    },
          onPanUpdate: (widget.onRemoteDrag == null &&
                  widget.onRemoteDragPath == null)
              ? null
              : (details) {
                  if (_dragStart == null) return;
                  _dragCurrent = _clampToContentRect(
                    details.localPosition,
                    contentRect,
                  );
                  // Sample densely for smooth remote swipes (1px min distance).
                  if (_dragPathPoints.isEmpty ||
                      (details.localPosition - _dragPathPoints.last).distance >
                          1) {
                    _dragPathPoints.add(details.localPosition);
                  }
                },
          onPanCancel:
              (widget.onRemoteDrag == null && widget.onRemoteDragPath == null)
                  ? null
                  : () {
                      _dragStart = null;
                      _dragCurrent = null;
                      _dragPathPoints.clear();
                    },
          onPanEnd:
              (widget.onRemoteDrag == null && widget.onRemoteDragPath == null)
                  ? null
                  : (_) {
                      final start = _dragStart;
                      final end = _dragCurrent;
                      final pathPoints = List<Offset>.from(_dragPathPoints);
                      _dragStart = null;
                      _dragCurrent = null;
                      _dragPathPoints.clear();
                      if (start == null || end == null) return;
                      if ((end - start).distance < threshold) return;

                      // Prefer path-based drag
                      if (widget.onRemoteDragPath != null &&
                          pathPoints.length >= 2) {
                        final sampled = _subsamplePath(pathPoints, 40);
                        final normalizedPath = sampled
                            .map((p) => toFrame(p))
                            .where((p) => p != null)
                            .cast<Offset>()
                            .toList();
                        if (normalizedPath.length >= 2) {
                          widget.onRemoteDragPath!(normalizedPath);
                          return;
                        }
                      }
                      if (widget.onRemoteDrag != null) {
                        final normalizedStart = toFrame(start);
                        final normalizedEnd = toFrame(end);
                        if (normalizedStart == null || normalizedEnd == null) {
                          return;
                        }
                        widget.onRemoteDrag!(normalizedStart, normalizedEnd);
                      }
                    },
          child: frameLayer,
        );
      },
    );
  }

  /// 按手指位移移动虚拟指针。
  ///
  /// 位移先除以画面在屏幕上的实际尺寸（含缩放），指针才会跟着手指等距走；
  /// 再按旋转档位转向，否则画面转了 90° 之后指针会往错误方向跑。
  void _movePointer(Offset screenDelta, Rect contentRect, int quarterTurns) {
    if (contentRect.width <= 0 || contentRect.height <= 0) return;
    final scale =
        widget.enableZoom ? _zoomController.value.getMaxScaleOnAxis() : 1.0;
    final displayDelta = Offset(
      screenDelta.dx / (contentRect.width * scale),
      screenDelta.dy / (contentRect.height * scale),
    );
    final frameDelta =
        CanvasRotation.displayDeltaToFrame(displayDelta, quarterTurns);
    setState(() {
      _pointerFramePos =
          CanvasRotation.clampNormalized(_pointerFramePos + frameDelta);
      if (_pointerDragArmed) {
        _pointerTrail.add(_pointerFramePos);
      }
    });
  }

  /// 一次指针拖动结束：武装状态下把轨迹作为拖拽发出，然后解除武装。
  void _flushPointerDrag() {
    if (!_pointerDragArmed || _pointerTrail.length < 2) {
      _pointerTrail.clear();
      return;
    }
    final path = _subsamplePath(List<Offset>.from(_pointerTrail), 24);
    _pointerTrail.clear();
    setState(() => _pointerDragArmed = false);
    widget.onRemoteDragPath?.call(path);
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

  /// Subsample a list of points to at most [maxPoints] evenly spaced entries,
  /// always keeping the first and last point.
  static List<Offset> _subsamplePath(List<Offset> points, int maxPoints) {
    if (points.length <= maxPoints) return points;
    final result = <Offset>[points.first];
    final step = (points.length - 1) / (maxPoints - 1);
    for (var i = 1; i < maxPoints - 1; i++) {
      result.add(points[(i * step).round()]);
    }
    result.add(points.last);
    return result;
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
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, _, __) {
              return Container(
                color: Colors.black,
                alignment: Alignment.center,
                child: const Text(
                  '画面解码失败，正在等待下一帧',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              );
            },
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
