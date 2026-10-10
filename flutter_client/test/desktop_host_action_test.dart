import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/services/desktop_host_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.qsw.rdesk/desktop_host');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    '展开所有窗口通过 RDesk 原生进程启动 Mission Control 执行器',
    () async {
      MethodCall? receivedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        receivedCall = call;
        return true;
      });

      final result = await DesktopHostService.instance
          .performRemoteAction('show_all_windows');

      expect(result, isTrue);
      expect(receivedCall?.method, 'launchMissionControlAction');
      expect(receivedCall?.arguments, <String, Object>{
        'action': 'show_all_windows',
      });
    },
    skip: !Platform.isMacOS,
  );

  test(
    '显示桌面通过 RDesk 原生进程启动 Mission Control 执行器',
    () async {
      MethodCall? receivedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        receivedCall = call;
        return true;
      });

      final result =
          await DesktopHostService.instance.performRemoteAction('show_desktop');

      expect(result, isTrue);
      expect(receivedCall?.method, 'launchMissionControlAction');
      expect(receivedCall?.arguments, <String, Object>{
        'action': 'show_desktop',
      });
    },
    skip: !Platform.isMacOS,
  );

  group('鼠标与文本输入走原生通道', () {
    final calls = <MethodCall>[];

    void mockChannel(Future<Object?> Function(MethodCall call) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        return handler(call);
      });
    }

    setUp(calls.clear);

    test(
      '点击发送 performMouse click 与归一化坐标',
      () async {
        mockChannel((_) async => true);

        final result = await DesktopHostService.instance
            .performRemoteTap(normalizedX: 0.25, normalizedY: 0.75);

        expect(result, isTrue);
        expect(calls.single.method, 'performMouse');
        expect(calls.single.arguments, <String, Object>{
          'kind': 'click',
          'x': 0.25,
          'y': 0.75,
        });
      },
      skip: !Platform.isMacOS,
    );

    test(
      '长按映射为 performMouse rightClick',
      () async {
        mockChannel((_) async => true);

        final result = await DesktopHostService.instance
            .performRemoteLongPress(normalizedX: 0.5, normalizedY: 0.1);

        expect(result, isTrue);
        expect(calls.single.method, 'performMouse');
        expect(calls.single.arguments, <String, Object>{
          'kind': 'rightClick',
          'x': 0.5,
          'y': 0.1,
        });
      },
      skip: !Platform.isMacOS,
    );

    test(
      '拖动发送 performMouse drag 与起止坐标',
      () async {
        mockChannel((_) async => true);

        final result = await DesktopHostService.instance.performRemoteDrag(
          startX: 0.1,
          startY: 0.2,
          endX: 0.8,
          endY: 0.9,
        );

        expect(result, isTrue);
        expect(calls.single.method, 'performMouse');
        expect(calls.single.arguments, <String, Object>{
          'kind': 'drag',
          'startX': 0.1,
          'startY': 0.2,
          'endX': 0.8,
          'endY': 0.9,
        });
      },
      skip: !Platform.isMacOS,
    );

    test(
      'scroll_up 与 scroll_down 发送方向相反的 performMouse scroll',
      () async {
        mockChannel((_) async => true);
        final service = DesktopHostService.instance;

        final up = await service.performRemoteAction('scroll_up');
        final down = await service.performRemoteAction('scroll_down');

        expect(up, isTrue);
        expect(down, isTrue);
        expect(calls.map((call) => call.method), [
          'performMouse',
          'performMouse',
        ]);
        expect(calls[0].arguments, <String, Object>{
          'kind': 'scroll',
          'deltaY': 3,
        });
        expect(calls[1].arguments, <String, Object>{
          'kind': 'scroll',
          'deltaY': -3,
        });
      },
      skip: !Platform.isMacOS,
    );

    test(
      '文本输入原样发送 performTextInput，不做转义',
      () async {
        mockChannel((_) async => true);
        const text = r'你好 "RDesk" \ 😀';

        final result =
            await DesktopHostService.instance.performRemoteTextInput(text);

        expect(result, isTrue);
        expect(calls.single.method, 'performTextInput');
        expect(calls.single.arguments, <String, Object>{'text': text});
      },
      skip: !Platform.isMacOS,
    );

    test(
      '原生侧拒绝注入时如实返回 false',
      () async {
        mockChannel((_) async => false);
        final service = DesktopHostService.instance;

        expect(
          await service.performRemoteTap(normalizedX: 0.5, normalizedY: 0.5),
          isFalse,
        );
        expect(await service.performRemoteTextInput('abc'), isFalse);
        expect(await service.performRemoteAction('scroll_up'), isFalse);
      },
      skip: !Platform.isMacOS,
    );

    test(
      '通道异常时返回 false 而不是向调用方抛出',
      () async {
        mockChannel(
          (_) async => throw PlatformException(code: 'INPUT_FAILED'),
        );
        final service = DesktopHostService.instance;

        expect(
          await service.performRemoteTap(normalizedX: 0.5, normalizedY: 0.5),
          isFalse,
        );
        expect(
          await service.performRemoteLongPress(
            normalizedX: 0.5,
            normalizedY: 0.5,
          ),
          isFalse,
        );
        expect(
          await service.performRemoteDrag(
            startX: 0.1,
            startY: 0.1,
            endX: 0.2,
            endY: 0.2,
          ),
          isFalse,
        );
        expect(await service.performRemoteTextInput('abc'), isFalse);
        expect(await service.performRemoteAction('scroll_down'), isFalse);
      },
      skip: !Platform.isMacOS,
    );

    test(
      '坐标不是有限数时不调用原生通道',
      () async {
        mockChannel((_) async => true);
        final service = DesktopHostService.instance;

        expect(
          await service.performRemoteTap(
            normalizedX: double.nan,
            normalizedY: 0.5,
          ),
          isFalse,
        );
        expect(
          await service.performRemoteDrag(
            startX: 0.1,
            startY: 0.1,
            endX: double.infinity,
            endY: 0.2,
          ),
          isFalse,
        );
        expect(calls, isEmpty);
      },
      skip: !Platform.isMacOS,
    );
  });
}
