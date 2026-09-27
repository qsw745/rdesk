import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/services/desktop_host_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.qsw.rdesk/desktop_host');
  final service = DesktopHostService.instance;
  var captures = 0;
  Completer<Map<String, Object>>? pending;

  setUp(() {
    captures = 0;
    pending = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getPermissionState') {
        return {'screenRecordingGranted': true, 'accessibilityGranted': true};
      }
      if (call.method == 'captureScreen') {
        captures++;
        return pending == null
            ? {
                'bytes': Uint8List.fromList([1, 2]),
                'width': 2,
                'height': 1
              }
            : pending!.future;
      }
      return null;
    });
  });

  tearDown(() async {
    await service.stopHosting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('在线待命调用取帧也不得采集', () async {
    await service.startHosting();
    expect(await service.getLatestFrame(), isNull);
    expect(captures, 0);
  });

  test('停止后丢弃迟到帧，重新连接可以重新采集', () async {
    await service.startHosting();
    await service.startCapture();
    pending = Completer<Map<String, Object>>();
    final frame = service.getLatestFrame();
    await Future<void>.delayed(Duration.zero);
    await service.stopCapture();
    pending!.complete({
      'bytes': Uint8List.fromList([1]),
      'width': 1,
      'height': 1
    });
    expect(await frame, isNull);
    expect(await service.getLatestFrame(), isNull);
    pending = null;
    await service.startCapture();
    expect(await service.getLatestFrame(), isNotNull);
    await service.stopHosting();
    await service.startCapture();
    expect(service.captureRunning, isFalse);
    expect(await service.getLatestFrame(), isNull);
  });
}
