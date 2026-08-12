import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/utils/canvas_rotation.dart';

void main() {
  group('CanvasRotation.displayToFrame', () {
    test('0 档原样返回', () {
      expect(
        CanvasRotation.displayToFrame(const Offset(0.2, 0.7), 0),
        const Offset(0.2, 0.7),
      );
    });

    test('90 档：显示空间右上角对应画面左上角', () {
      // RotatedBox 顺时针旋转，画面 (0,0) 会被转到显示空间 (1,0)。
      expect(
        CanvasRotation.displayToFrame(const Offset(1, 0), 1),
        const Offset(0, 0),
      );
      expect(
        CanvasRotation.displayToFrame(const Offset(0, 0), 1),
        const Offset(0, 1),
      );
    });

    test('180 档：对角翻转', () {
      expect(
        CanvasRotation.displayToFrame(const Offset(0.25, 0.75), 2),
        const Offset(0.75, 0.25),
      );
    });

    test('270 档：显示空间左下角对应画面左上角', () {
      expect(
        CanvasRotation.displayToFrame(const Offset(0, 1), 3),
        const Offset(0, 0),
      );
    });
  });

  group('CanvasRotation.frameToDisplay', () {
    test('是 displayToFrame 的逆运算', () {
      const points = [
        Offset(0, 0),
        Offset(1, 0),
        Offset(0.3, 0.8),
        Offset(0.5, 0.5),
      ];
      for (var turns = 0; turns < CanvasRotation.turnCount; turns++) {
        for (final point in points) {
          final roundTrip = CanvasRotation.displayToFrame(
            CanvasRotation.frameToDisplay(point, turns),
            turns,
          );
          expect(roundTrip.dx, closeTo(point.dx, 1e-9),
              reason: 'turns=$turns point=$point');
          expect(roundTrip.dy, closeTo(point.dy, 1e-9),
              reason: 'turns=$turns point=$point');
        }
      }
    });
  });

  group('CanvasRotation.displayDeltaToFrame', () {
    test('位移只转向、不做原点平移', () {
      const right = Offset(0.1, 0);
      expect(CanvasRotation.displayDeltaToFrame(right, 0), right);
      // 画面顺时针转 90° 显示后，手指往右等于在画面里往上。
      expect(
        CanvasRotation.displayDeltaToFrame(right, 1),
        const Offset(0, -0.1),
      );
      expect(
        CanvasRotation.displayDeltaToFrame(right, 2),
        const Offset(-0.1, 0),
      );
      expect(
        CanvasRotation.displayDeltaToFrame(right, 3),
        const Offset(0, 0.1),
      );
    });

    test('位移换算与坐标换算方向一致', () {
      const from = Offset(0.4, 0.4);
      const to = Offset(0.6, 0.4);
      for (var turns = 0; turns < CanvasRotation.turnCount; turns++) {
        final mappedDelta =
            CanvasRotation.displayDeltaToFrame(to - from, turns);
        final expected = CanvasRotation.displayToFrame(to, turns) -
            CanvasRotation.displayToFrame(from, turns);
        expect(mappedDelta.dx, closeTo(expected.dx, 1e-9), reason: '$turns');
        expect(mappedDelta.dy, closeTo(expected.dy, 1e-9), reason: '$turns');
      }
    });
  });

  group('CanvasRotation.displaySize', () {
    test('奇数档宽高互换', () {
      const frame = Size(1080, 2400);
      expect(CanvasRotation.displaySize(frame, 0), frame);
      expect(CanvasRotation.displaySize(frame, 1), const Size(2400, 1080));
      expect(CanvasRotation.displaySize(frame, 2), frame);
      expect(CanvasRotation.displaySize(frame, 3), const Size(2400, 1080));
    });
  });

  group('CanvasRotation.clampNormalized', () {
    test('超出画面的坐标被夹回边界', () {
      expect(
        CanvasRotation.clampNormalized(const Offset(-0.3, 1.8)),
        const Offset(0, 1),
      );
    });
  });
}
