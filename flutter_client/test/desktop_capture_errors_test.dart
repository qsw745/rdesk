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
  int? sequence;

  setUp(() async {
    captureError = null;
    sequence = null;
    nativeMessage = 'native text';
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'captureScreen' && captureError != null) {
        throw PlatformException(code: captureError!, message: nativeMessage);
      }
      if (call.method == 'captureScreen') {
        return {
          'bytes': Uint8List.fromList([1, 2, 3]),
          'width': 3,
          'height': 1,
          if (sequence != null) 'sequence': sequence,
        };
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

  test('画面序号不变时返回同一帧，调用方据此不重复上传', () async {
    sequence = 7;
    final first = await service.getLatestFrame();
    final second = await service.getLatestFrame();

    expect(first, isNotNull);
    expect(identical(first, second), isTrue);
    expect(second!.timestampMs, first!.timestampMs);
  }, skip: !(Platform.isMacOS || Platform.isWindows));

  test('画面序号变化时返回新的一帧', () async {
    sequence = 7;
    final first = await service.getLatestFrame();
    sequence = 8;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final second = await service.getLatestFrame();

    expect(identical(first, second), isFalse);
    expect(second!.timestampMs, greaterThan(first!.timestampMs));
  }, skip: !(Platform.isMacOS || Platform.isWindows));

  test('原生层不提供序号时每次都是新帧，行为与以前一致', () async {
    final first = await service.getLatestFrame();
    final second = await service.getLatestFrame();

    expect(identical(first, second), isFalse);
  }, skip: !(Platform.isMacOS || Platform.isWindows));
}
