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
}
