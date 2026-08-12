import 'dart:ui';

/// 远程画面旋转显示时的坐标换算（一档 = 顺时针 90°）。
///
/// 旋转只发生在观看端：画面按档位转过来铺给用户看，手指落点因此位于「显示
/// 空间」，而被控端只认原始画面的归一化坐标（「画面空间」）。两者必须互转，
/// 否则旋转之后点哪都会偏。
class CanvasRotation {
  const CanvasRotation._();

  /// 档位总数（0°、90°、180°、270°）。
  static const int turnCount = 4;

  /// 归一化的显示空间坐标 → 画面空间坐标。
  static Offset displayToFrame(Offset display, int quarterTurns) {
    switch (quarterTurns % turnCount) {
      case 1:
        return Offset(display.dy, 1 - display.dx);
      case 2:
        return Offset(1 - display.dx, 1 - display.dy);
      case 3:
        return Offset(1 - display.dy, display.dx);
      default:
        return display;
    }
  }

  /// 归一化的画面空间坐标 → 显示空间坐标（用于画本地指针）。
  static Offset frameToDisplay(Offset frame, int quarterTurns) {
    switch (quarterTurns % turnCount) {
      case 1:
        return Offset(1 - frame.dy, frame.dx);
      case 2:
        return Offset(1 - frame.dx, 1 - frame.dy);
      case 3:
        return Offset(frame.dy, 1 - frame.dx);
      default:
        return frame;
    }
  }

  /// 位移向量换算：只转方向，不做原点平移。
  static Offset displayDeltaToFrame(Offset delta, int quarterTurns) {
    switch (quarterTurns % turnCount) {
      case 1:
        return Offset(delta.dy, -delta.dx);
      case 2:
        return Offset(-delta.dx, -delta.dy);
      case 3:
        return Offset(-delta.dy, delta.dx);
      default:
        return delta;
    }
  }

  /// 旋转后画面在显示空间的尺寸：奇数档宽高互换。
  static Size displaySize(Size frameSize, int quarterTurns) =>
      quarterTurns % 2 == 1
          ? Size(frameSize.height, frameSize.width)
          : frameSize;

  /// 把归一化坐标限制在画面内。
  static Offset clampNormalized(Offset position) => Offset(
        position.dx.clamp(0.0, 1.0),
        position.dy.clamp(0.0, 1.0),
      );
}
