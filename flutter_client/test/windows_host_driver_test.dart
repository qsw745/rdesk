import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/services/windows_host_driver.dart';
import 'package:rdesk/src/utils/remote_key_action.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.qsw.rdesk/desktop_host');
  const driver = WindowsHostDriver(channel);
  final calls = <MethodCall>[];
  Object? reply = true;

  setUp(() {
    calls.clear();
    reply = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final value = reply;
      if (value is PlatformException) throw value;
      return value;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('按键映射', () {
    test('方向键与编辑键映射为 Windows 虚拟键码', () {
      expect(windowsRemoteKeyStrokeForAction('key_escape')?.virtualKey, 0x1B);
      expect(
          windowsRemoteKeyStrokeForAction('key_arrow_left')?.virtualKey, 0x25);
      expect(windowsRemoteKeyStrokeForAction('delete')?.virtualKey, 0x08);
      expect(windowsRemoteKeyStrokeForAction('enter')?.virtualKey, 0x0D);
      expect(windowsRemoteKeyStrokeForAction('enter')?.modifiers, isEmpty);
    });

    test('观看端的 Command 组合在 Windows 上改用 Ctrl', () {
      final copy = windowsRemoteKeyStrokeForAction('key_command_c');
      expect(copy?.virtualKey, 0x43);
      expect(copy?.modifiers, {WindowsRemoteModifier.control});
      final redo = windowsRemoteKeyStrokeForAction('key_command_shift_z');
      expect(redo?.virtualKey, 0x59);
      expect(redo?.modifiers, {WindowsRemoteModifier.control});
    });

    test('窗口动作使用 Win 组合，旧版观看端的安卓动作有对应按键', () {
      final desktop = windowsRemoteKeyStrokeForAction('show_desktop');
      expect(desktop?.virtualKey, 0x44);
      expect(desktop?.modifiers, {WindowsRemoteModifier.win});
      expect(windowsRemoteKeyStrokeForAction('task_view')?.virtualKey, 0x09);
      expect(windowsRemoteKeyStrokeForAction('recents')?.modifiers,
          {WindowsRemoteModifier.win});
      expect(windowsRemoteKeyStrokeForAction('back')?.modifiers,
          {WindowsRemoteModifier.alt});
    });

    test('未知动作和 macOS 专用动作不生成按键', () {
      expect(windowsRemoteKeyStrokeForAction('show_all_windows'), isNull);
      expect(windowsRemoteKeyStrokeForAction('wake_screen'), isNull);
      expect(windowsRemoteKeyStrokeForAction('key_not_supported'), isNull);
    });
  });

  group('输入', () {
    test('单击与右键通过原生通道发送归一化坐标', () async {
      expect(await driver.click(0.25, 0.75), isTrue);
      expect(await driver.rightClick(0.5, 0.5), isTrue);

      expect(calls.map((c) => c.method), ['performMouse', 'performMouse']);
      expect(calls[0].arguments, {'kind': 'click', 'x': 0.25, 'y': 0.75});
      expect(calls[1].arguments, {'kind': 'rightClick', 'x': 0.5, 'y': 0.5});
    });

    test('拖动携带起止坐标', () async {
      await driver.drag(0.1, 0.2, 0.3, 0.4);

      expect(calls.single.arguments,
          {'kind': 'drag', 'x': 0.1, 'y': 0.2, 'endX': 0.3, 'endY': 0.4});
    });

    test('超出画面的坐标被拒绝且不触达原生层', () async {
      expect(await driver.click(1.2, 0.5), isFalse);
      expect(await driver.drag(0.1, 0.1, double.nan, 0.2), isFalse);
      expect(calls, isEmpty);
    });

    test('文本原样交给原生层，空文本不发送', () async {
      expect(await driver.typeText('你好 😀'), isTrue);
      expect(await driver.typeText(''), isFalse);

      expect(calls.single.method, 'typeText');
      expect(calls.single.arguments, {'text': '你好 😀'});
    });

    test('原生层报告注入失败时如实返回失败', () async {
      reply = false;
      expect(await driver.click(0.5, 0.5), isFalse);
      reply = PlatformException(code: 'INPUT_BLOCKED');
      expect(await driver.click(0.5, 0.5), isFalse);
    });
  });

  group('动作', () {
    test('按键动作发送虚拟键码与修饰键名', () async {
      expect(await driver.performAction('key_command_a'), isTrue);

      expect(calls.single.method, 'performKeyPress');
      expect(calls.single.arguments, {
        'keyCode': 0x41,
        'modifiers': ['control'],
      });
    });

    test('滚动与唤醒屏幕走各自的原生方法', () async {
      await driver.performAction('scroll_up');
      await driver.performAction('scroll_down');
      await driver.performAction('wake_screen');

      expect(calls[0].arguments, {'kind': 'scroll', 'amount': 3});
      expect(calls[1].arguments, {'kind': 'scroll', 'amount': -3});
      expect(calls[2].method, 'wakeDisplay');
    });

    test('切换显示器只接受非负序号', () async {
      expect(await driver.performAction('switch_monitor_1'), isTrue);
      expect(await driver.performAction('switch_monitor_-1'), isFalse);
      expect(await driver.performAction('switch_monitor_x'), isFalse);

      expect(calls.single.method, 'switchDisplay');
      expect(calls.single.arguments, {'index': 1});
    });

    test('不支持的动作返回失败而不是静默成功', () async {
      expect(await driver.performAction('show_all_windows'), isFalse);
      expect(calls, isEmpty);
    });
  });
}
