import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/models/key_mapping.dart';
import 'package:rdesk/src/utils/hardware_key_forwarding.dart';
import 'package:rdesk/src/utils/remote_key_action.dart';
import 'package:rdesk/src/utils/remote_peer_platform.dart';

RemoteKeyOutput? press(
  PhysicalKeyboardKey physical,
  LogicalKeyboardKey logical, {
  String? character,
  bool meta = false,
  bool control = false,
  bool alt = false,
  bool shift = false,
  RemotePeerPlatform remote = RemotePeerPlatform.windows,
  TargetPlatform viewer = TargetPlatform.macOS,
  WindowsKeyMapping mapping = WindowsKeyMapping.defaults,
}) =>
    translateHardwareKey(
      remote: remote,
      viewer: viewer,
      physical: physical,
      logical: logical,
      character: character,
      meta: meta,
      control: control,
      alt: alt,
      shift: shift,
      mapping: mapping,
    );

String? action(RemoteKeyOutput? output) =>
    output is RemoteKeyAction ? output.action : null;
String? text(RemoteKeyOutput? output) =>
    output is RemoteKeyText ? output.text : null;

void main() {
  const a = PhysicalKeyboardKey.keyA;
  const la = LogicalKeyboardKey.keyA;

  group('Mac 控制 Windows', () {
    test('普通字符按文字发送，Shift 只影响字符本身', () {
      expect(text(press(a, la, character: 'a')), 'a');
      expect(text(press(a, la, character: 'A', shift: true)), 'A');
      expect(
          text(press(PhysicalKeyboardKey.digit1, LogicalKeyboardKey.digit1,
              character: '!', shift: true)),
          '!');
    });

    test('默认映射：Command 为 Win，Option 为 Alt，Control 为 Ctrl', () {
      expect(action(press(a, la, character: 'a', meta: true)), 'key:win+a');
      expect(action(press(a, la, character: 'å', alt: true)), 'key:alt+a');
      expect(action(press(a, la, control: true)), 'key:ctrl+a');
      expect(
          action(press(PhysicalKeyboardKey.keyZ, LogicalKeyboardKey.keyZ,
              control: true, shift: true)),
          'key:ctrl+shift+z');
    });

    test('把 Command 改成 Ctrl 后，Command+C 发送 Ctrl+C', () {
      const mapping = WindowsKeyMapping(command: RemoteModifier.ctrl);

      expect(
          action(press(PhysicalKeyboardKey.keyC, LogicalKeyboardKey.keyC,
              meta: true, mapping: mapping)),
          'key:ctrl+c');
    });

    test('两个本地修饰键映射到同一个键时只发一次', () {
      const mapping = WindowsKeyMapping(command: RemoteModifier.ctrl);

      expect(action(press(a, la, meta: true, control: true, mapping: mapping)),
          'key:ctrl+a');
    });

    test('Delete 默认是退格，Fn+Delete 默认是向前删除，均可互换', () {
      const back = PhysicalKeyboardKey.backspace;
      const del = PhysicalKeyboardKey.delete;
      expect(action(press(back, LogicalKeyboardKey.backspace)),
          'key:backspace');
      expect(action(press(del, LogicalKeyboardKey.delete)), 'key:delete');

      const swapped = WindowsKeyMapping(
          delete: DeleteKeyTarget.delete, fnDelete: DeleteKeyTarget.backspace);
      expect(
          action(press(back, LogicalKeyboardKey.backspace, mapping: swapped)),
          'key:delete');
      expect(action(press(del, LogicalKeyboardKey.delete, mapping: swapped)),
          'key:backspace');
    });

    test('功能键、方向键和带修饰键的组合按按键发送', () {
      expect(
          action(press(PhysicalKeyboardKey.enter, LogicalKeyboardKey.enter,
              character: '\r')),
          'key:enter');
      expect(
          action(press(
              PhysicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowLeft,
              shift: true)),
          'key:shift+left');
      expect(
          action(press(PhysicalKeyboardKey.f4, LogicalKeyboardKey.f4,
              alt: true)),
          'key:alt+f4');
      expect(
          action(press(PhysicalKeyboardKey.tab, LogicalKeyboardKey.tab,
              alt: true)),
          'key:alt+tab');
      expect(
          action(press(PhysicalKeyboardKey.slash, LogicalKeyboardKey.slash,
              control: true)),
          'key:ctrl+slash');
    });

    test('退出、关闭、隐藏、最小化这几个 Mac 快捷键留在本机', () {
      for (final (physical, logical) in [
        (PhysicalKeyboardKey.keyQ, LogicalKeyboardKey.keyQ),
        (PhysicalKeyboardKey.keyW, LogicalKeyboardKey.keyW),
        (PhysicalKeyboardKey.keyH, LogicalKeyboardKey.keyH),
        (PhysicalKeyboardKey.keyM, LogicalKeyboardKey.keyM),
      ]) {
        expect(press(physical, logical, meta: true), isNull);
      }
      // Only the Command combinations: Ctrl+W still closes a remote tab.
      expect(
          action(press(PhysicalKeyboardKey.keyW, LogicalKeyboardKey.keyW,
              control: true)),
          'key:ctrl+w');
      // And only on a Mac keyboard.
      expect(
          action(press(PhysicalKeyboardKey.keyM, LogicalKeyboardKey.keyM,
              meta: true, viewer: TargetPlatform.windows)),
          'key:win+m');
    });

    test('单独按修饰键或无法识别的键不发送', () {
      expect(
          press(PhysicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaLeft,
              meta: true),
          isNull);
      expect(
          press(PhysicalKeyboardKey.capsLock, LogicalKeyboardKey.capsLock),
          isNull);
      expect(
          press(PhysicalKeyboardKey.audioVolumeUp,
              LogicalKeyboardKey.audioVolumeUp),
          isNull);
      // macOS reports function-row extras as private-use characters.
      expect(
          press(PhysicalKeyboardKey.help, LogicalKeyboardKey.help,
              character: ''),
          isNull);
    });
  });

  test('Windows 控制 Windows 时修饰键原样对应，不受 Mac 映射影响', () {
    const mapping = WindowsKeyMapping(control: RemoteModifier.win);

    expect(
        action(press(PhysicalKeyboardKey.keyC, LogicalKeyboardKey.keyC,
            control: true, viewer: TargetPlatform.windows, mapping: mapping)),
        'key:ctrl+c');
  });

  group('被控端不是 Windows', () {
    test('Mac 被控端只发送它已实现的按键', () {
      const remote = RemotePeerPlatform.mac;
      expect(text(press(a, la, character: 'a', remote: remote)), 'a');
      expect(
          action(press(PhysicalKeyboardKey.keyC, LogicalKeyboardKey.keyC,
              meta: true, remote: remote)),
          'key_command_c');
      expect(
          action(press(PhysicalKeyboardKey.keyZ, LogicalKeyboardKey.keyZ,
              meta: true, shift: true, remote: remote)),
          'key_command_shift_z');
      expect(
          action(press(PhysicalKeyboardKey.escape, LogicalKeyboardKey.escape,
              remote: remote)),
          'key_escape');
      expect(
          action(press(
              PhysicalKeyboardKey.backspace, LogicalKeyboardKey.backspace,
              remote: remote)),
          'delete');
      expect(
          press(PhysicalKeyboardKey.keyQ, LogicalKeyboardKey.keyQ,
              meta: true, remote: remote),
          isNull);
      expect(
          press(PhysicalKeyboardKey.f5, LogicalKeyboardKey.f5, remote: remote),
          isNull);
    });

    test('Windows 上按 Ctrl+C 控制 Mac 时发送复制', () {
      expect(
          action(press(PhysicalKeyboardKey.keyC, LogicalKeyboardKey.keyC,
              control: true,
              remote: RemotePeerPlatform.mac,
              viewer: TargetPlatform.windows)),
          'key_command_c');
    });

    test('安卓被控端只有文字、删除和回车', () {
      const remote = RemotePeerPlatform.android;
      expect(text(press(a, la, character: 'a', remote: remote)), 'a');
      expect(
          action(press(PhysicalKeyboardKey.enter, LogicalKeyboardKey.enter,
              remote: remote)),
          'enter');
      expect(
          action(press(
              PhysicalKeyboardKey.backspace, LogicalKeyboardKey.backspace,
              remote: remote)),
          'delete');
      expect(
          press(PhysicalKeyboardKey.escape, LogicalKeyboardKey.escape,
              remote: remote),
          isNull);
      expect(press(a, la, control: true, remote: remote), isNull);
    });
  });

  group('映射设置', () {
    test('可保存并读回，损坏或未知的值回到默认', () {
      const mapping = WindowsKeyMapping(
          command: RemoteModifier.ctrl, delete: DeleteKeyTarget.delete);

      expect(WindowsKeyMapping.fromJson(mapping.toJson()), mapping);
      expect(WindowsKeyMapping.fromJson(const {'command': 'hyper'}),
          WindowsKeyMapping.defaults);
      expect(WindowsKeyMapping.fromJson(null), WindowsKeyMapping.defaults);
    });
  });

  group('被控端解析按键指令', () {
    test('组合键解析为虚拟键码与修饰键', () {
      final copy = windowsRemoteKeyStrokeForAction('key:ctrl+c');
      expect(copy?.virtualKey, 0x43);
      expect(copy?.modifiers, {WindowsRemoteModifier.control});

      final close = windowsRemoteKeyStrokeForAction('key:alt+f4');
      expect(close?.virtualKey, 0x73);
      expect(close?.modifiers, {WindowsRemoteModifier.alt});

      final run = windowsRemoteKeyStrokeForAction('key:win+r');
      expect(run?.virtualKey, 0x52);
      expect(run?.modifiers, {WindowsRemoteModifier.win});

      expect(windowsRemoteKeyStrokeForAction('key:delete')?.virtualKey, 0x2E);
      expect(windowsRemoteKeyStrokeForAction('key:backspace')?.virtualKey, 0x08);
      expect(windowsRemoteKeyStrokeForAction('key:shift+left')?.modifiers,
          {WindowsRemoteModifier.shift});
      expect(windowsRemoteKeyStrokeForAction('key:ctrl+slash')?.virtualKey, 0xBF);
      expect(windowsRemoteKeyStrokeForAction('key:5')?.virtualKey, 0x35);
    });

    test('格式不对、未知按键或未知修饰键一律拒绝', () {
      for (final bad in [
        'key:',
        'key:ctrl+',
        'key:hyper+a',
        'key:ctrl+nosuchkey',
        'key:ctrl+ctrl+ctrl+ctrl+ctrl+a',
        'key:a+b',
        'key:CTRL+A',
      ]) {
        expect(windowsRemoteKeyStrokeForAction(bad), isNull, reason: bad);
      }
    });

    test('旧的动作名仍然可用', () {
      expect(windowsRemoteKeyStrokeForAction('key_command_c')?.virtualKey, 0x43);
      expect(windowsRemoteKeyStrokeForAction('enter')?.virtualKey, 0x0D);
    });
  });

  group('发送队列', () {
    test('保持按键顺序，并把等待期间连续输入的文字合并成一次发送', () async {
      final sent = <String>[];
      final gate = Completer<void>();
      final queue = RemoteKeyQueue(
        sendText: (value) async {
          sent.add('text:$value');
          if (sent.length == 1) await gate.future;
        },
        sendAction: (value) async => sent.add('action:$value'),
      );

      queue.add(const RemoteKeyText('h'));
      queue.add(const RemoteKeyText('e'));
      queue.add(const RemoteKeyText('y'));
      queue.add(const RemoteKeyAction('key:enter'));
      queue.add(const RemoteKeyText('!'));
      await Future<void>.delayed(Duration.zero);
      expect(sent, ['text:h']);

      gate.complete();
      await queue.idle;

      expect(sent, ['text:h', 'text:ey', 'action:key:enter', 'text:!']);
    });

    test('发送失败不会卡住后面的按键', () async {
      final sent = <String>[];
      final queue = RemoteKeyQueue(
        sendText: (value) async => throw StateError('offline'),
        sendAction: (value) async => sent.add(value),
      );

      queue.add(const RemoteKeyText('a'));
      queue.add(const RemoteKeyAction('key:enter'));
      await queue.idle;

      expect(sent, ['key:enter']);
    });

    test('积压过多时丢弃新按键，而不是事后一股脑打出来', () async {
      final sent = <String>[];
      final gate = Completer<void>();
      final queue = RemoteKeyQueue(
        sendText: (value) async {},
        sendAction: (value) async {
          sent.add(value);
          await gate.future;
        },
      );

      for (var i = 0; i < RemoteKeyQueue.maxPending + 20; i++) {
        queue.add(RemoteKeyAction('key:$i'));
      }
      gate.complete();
      await queue.idle;

      expect(sent.length, lessThanOrEqualTo(RemoteKeyQueue.maxPending + 1));
    });
  });
}
