import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/canvas_rotation.dart';
import '../utils/theme.dart';

/// 指针模式的本地叠加层：一个虚拟指针 + 右侧按钮组。
///
/// 被控端（安卓无障碍注入）只有触摸语义，没有系统光标可驱动，所以指针完全画
/// 在观看端：拖动屏幕移动指针，按钮把点击/长按/拖拽落在指针当前位置。这样在
/// 手机上点小控件不再靠手指盲按。
class RemotePointerLayer extends StatelessWidget {
  const RemotePointerLayer({
    super.key,
    required this.zoom,
    required this.contentRect,
    required this.pointerFramePosition,
    required this.quarterTurns,
    required this.dragArmed,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleDrag,
  });

  /// 画布的缩放/平移矩阵，指针要跟着画面走但自身不被放大。
  final ValueListenable<Matrix4> zoom;

  /// 画面在视口中的实际矩形（未缩放）。
  final Rect contentRect;

  /// 指针位置，画面空间的归一化坐标。
  final Offset pointerFramePosition;
  final int quarterTurns;

  /// 是否已武装拖拽：下一次拖动会作为拖拽发给被控端。
  final bool dragArmed;

  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleDrag;

  static const double _cursorSize = 30;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _buildCursor(),
        Positioned(
          right: 12,
          top: 0,
          bottom: 0,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PointerButton(
                  icon: Icons.touch_app_outlined,
                  label: '点击',
                  onTap: onTap,
                ),
                const SizedBox(height: 10),
                _PointerButton(
                  icon: Icons.more_time_rounded,
                  label: '长按',
                  onTap: onLongPress,
                ),
                const SizedBox(height: 10),
                _PointerButton(
                  icon: Icons.open_with_rounded,
                  label: '拖拽',
                  active: dragArmed,
                  onTap: onToggleDrag,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCursor() {
    return ValueListenableBuilder<Matrix4>(
      valueListenable: zoom,
      builder: (context, matrix, _) {
        final display =
            CanvasRotation.frameToDisplay(pointerFramePosition, quarterTurns);
        final contentPoint = Offset(
          contentRect.left + display.dx * contentRect.width,
          contentRect.top + display.dy * contentRect.height,
        );
        final screenPoint = MatrixUtils.transformPoint(matrix, contentPoint);
        return Positioned(
          left: screenPoint.dx - _cursorSize / 2,
          top: screenPoint.dy - _cursorSize / 2,
          child: IgnorePointer(
            child: _Cursor(armed: dragArmed),
          ),
        );
      },
    );
  }
}

class _Cursor extends StatelessWidget {
  const _Cursor({required this.armed});

  final bool armed;

  @override
  Widget build(BuildContext context) {
    final accent = armed ? AppTheme.primaryBlue : Colors.white;
    return Container(
      width: RemotePointerLayer._cursorSize,
      height: RemotePointerLayer._cursorSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: armed ? 0.28 : 0.14),
        border: Border.all(color: accent, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 6,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent,
          ),
        ),
      ),
    );
  }
}

class _PointerButton extends StatelessWidget {
  const _PointerButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? AppTheme.primaryBlue
                : Colors.black.withValues(alpha: 0.55),
            border: Border.all(
              color: Colors.white.withValues(alpha: active ? 0.0 : 0.16),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: Colors.white),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
