import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/services/desktop_host_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.qsw.rdesk/desktop_host');
  final service = DesktopHostService.instance;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  String? captureError;
  String? nativeMessage;

  setUp(() async {
    captureError = null;
    nativeMessage = 'native text';
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'captureScreen' && captureError != null) {
        throw PlatformException(code: captureError!, message: nativeMessage);
      }
      return null;
    });
    await service.startHosting();
    await service.startCapture();
  });

  tearDown(() async {
    await service.stopHosting();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<DesktopPermissionException> failure(String code) async {
    captureError = code;
    try {
      await service.getLatestFrame();
    } on DesktopPermissionException catch (error) {
      return error;
    }
    fail('expected $code to surface as a capture failure');
  }

  test('锁屏时给出明确原因而不是权限或通用失败', () async {
    final error = await failure('SESSION_LOCKED');

    expect(error.code, 'session_locked');
    expect(error.message, contains('锁屏'));
  }, skip: !(Platform.isMacOS || Platform.isWindows));

  test('系统安全界面占用屏幕时说明暂时无法查看', () async {
    final error = await failure('SECURE_DESKTOP');

    expect(error.code, 'secure_desktop');
    expect(error.message, contains('安全界面'));
    expect(error.message, isNot(contains('native text')));
  }, skip: !(Platform.isMacOS || Platform.isWindows));

  test('原生层给出的失败说明保留在提示里', () async {
    final error = await failure('CAPTURE_FAILED');

    expect(error.code, 'capture_failed');
    expect(error.message, '屏幕采集失败：native text');
  }, skip: !(Platform.isMacOS || Platform.isWindows));

  test('原生层没有说明时提示里不出现 null', () async {
    nativeMessage = null;
    final error = await failure('CAPTURE_FAILED');

    expect(error.message, '屏幕采集失败');
  }, skip: !(Platform.isMacOS || Platform.isWindows));
}
