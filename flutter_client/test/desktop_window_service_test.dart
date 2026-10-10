import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/services/desktop_window_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.qsw.rdesk/window');
  const windows = DesktopWindowService(platform: TargetPlatform.windows);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    windows.onHostRequests();
  });

  test('被查看状态通知托盘，其他平台不调用', () async {
    await windows.setViewerActive(true);
    await const DesktopWindowService(platform: TargetPlatform.macOS)
        .setViewerActive(true);

    expect(calls.single.method, 'setViewerActive');
    expect(calls.single.arguments, isTrue);
  });

  test('托盘的断开与停止被控请求分别转给注册的处理函数', () async {
    final requests = <String>[];
    windows.onHostRequests(
      disconnect: () async => requests.add('disconnect'),
      stopHosting: () async => requests.add('stop'),
    );

    for (final method in ['disconnectViewers', 'stopHosting', 'unknown']) {
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
        (_) {},
      );
    }

    expect(requests, ['disconnect', 'stop']);
  });

  test('旧版 runner 没有托盘通道时不抛出', () async {
    messenger.setMockMethodCallHandler(channel, null);

    await expectLater(windows.setViewerActive(true), completes);
  });
}
