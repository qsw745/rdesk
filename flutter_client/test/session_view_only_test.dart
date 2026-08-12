import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/providers/session_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('仅观看模式', () {
    test('默认关闭', () {
      final provider = SessionProvider();
      addTearDown(provider.dispose);
      expect(provider.viewOnly, isFalse);
    });

    test('开启后所有输入都被丢弃且不触达桥接层', () async {
      final provider = SessionProvider();
      addTearDown(provider.dispose);
      provider.toggleViewOnly();

      expect(provider.viewOnly, isTrue);
      // 没有活动会话，桥接层一旦被调用就会抛错或发起网络请求；
      // 这里全部返回 false 说明请求在 provider 层就被拦掉了。
      expect(await provider.sendNormalizedTap('s', const Offset(0.5, 0.5)),
          isFalse);
      expect(
        await provider.sendNormalizedLongPress('s', const Offset(0.5, 0.5)),
        isFalse,
      );
      expect(
        await provider.sendNormalizedDrag(
            's', const Offset(0.1, 0.1), const Offset(0.9, 0.9)),
        isFalse,
      );
      expect(
        await provider.sendNormalizedDragPath(
            's', const [Offset(0.1, 0.1), Offset(0.9, 0.9)]),
        isFalse,
      );
      expect(await provider.sendAction('s', 'home'), isFalse);
      expect(await provider.sendTextInput('s', 'hello'), isFalse);
      expect(await provider.sendClipboard('s', 'hello'), isFalse);
    });

    test('再次切换即恢复控制', () {
      final provider = SessionProvider();
      addTearDown(provider.dispose);
      provider.toggleViewOnly();
      provider.toggleViewOnly();
      expect(provider.viewOnly, isFalse);
    });
  });

  group('画面旋转与指针模式', () {
    test('旋转四次回到 0 档', () {
      final provider = SessionProvider();
      addTearDown(provider.dispose);
      expect(provider.rotationQuarterTurns, 0);
      provider.rotateCanvas();
      expect(provider.rotationQuarterTurns, 1);
      provider.rotateCanvas();
      provider.rotateCanvas();
      expect(provider.rotationQuarterTurns, 3);
      provider.rotateCanvas();
      expect(provider.rotationQuarterTurns, 0);
    });

    test('resetCanvasRotation 直接回正', () {
      final provider = SessionProvider();
      addTearDown(provider.dispose);
      provider.rotateCanvas();
      provider.rotateCanvas();
      provider.resetCanvasRotation();
      expect(provider.rotationQuarterTurns, 0);
    });

    test('指针模式可开可关', () {
      final provider = SessionProvider();
      addTearDown(provider.dispose);
      expect(provider.pointerMode, isFalse);
      provider.togglePointerMode();
      expect(provider.pointerMode, isTrue);
      provider.togglePointerMode();
      expect(provider.pointerMode, isFalse);
    });

    test('清空会话时三个开关都复位', () {
      final provider = SessionProvider();
      addTearDown(provider.dispose);
      provider.toggleViewOnly();
      provider.togglePointerMode();
      provider.rotateCanvas();

      provider.clearSession();

      expect(provider.viewOnly, isFalse);
      expect(provider.pointerMode, isFalse);
      expect(provider.rotationQuarterTurns, 0);
    });
  });
}
