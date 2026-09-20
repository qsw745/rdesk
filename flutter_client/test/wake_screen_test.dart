import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:rdesk/src/services/windows_wake_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rdesk/src/models/wake.dart';
import 'package:rdesk/src/providers/wake_provider.dart';
import 'package:rdesk/src/services/wake_api.dart';
import 'package:rdesk/src/screens/wake_screen.dart';
import 'wake_provider_test.dart' show TestAgent;

class ScreenWake extends WakeProvider {
  ScreenWake({WindowsWakeService? windows})
      : super(
            api: WakeApi(
                baseUri: () async => Uri.parse('https://example.test'),
                accountToken: () async => 'token'),
            agent: TestAgent(),
            windows: windows);
  @override
  Future<void> refresh() async {}
  void replaceAgents(List<WakeAgent> value) {
    agents = value;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.qsw.rdesk/windows_wake');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel,
            (_) async => {
                  'schema': 1,
                  'source': 'ip_helper',
                  'elapsed_ms': 1,
                  'adapters': [
                    {
                      'id': 'wired',
                      'name': '以太网',
                      'mac': '02:11:22:33:44:55',
                      'if_type': 6,
                      'hardware': true,
                      'connected': true
                    }
                  ]
                });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  testWidgets('检测失败显示诊断，不误报没有有线网卡', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel,
            (_) async => throw PlatformException(code: 'adapter_query'));
    final api = WakeApi(
        baseUri: () async => Uri.parse('https://example.test'),
        accountToken: () async => 'a');
    final windows = WindowsWakeService(
        api: api,
        storage: const FlutterSecureStorage(),
        run: (_, __) async => ProcessResult(0, 0, '', ''));
    final wake = ScreenWake(windows: windows);
    await wake.bindAccount('user', 'server');
    await tester.pumpWidget(ChangeNotifierProvider<WakeProvider>.value(
        value: wake, child: const MaterialApp(home: WakeSetupScreen())));
    await tester.pumpAndSettle();
    expect(find.textContaining('网卡检测失败'), findsWidgets);
    expect(find.text('未找到已连接的有线网卡'), findsNothing);
    expect(find.text('查看诊断'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    wake.dispose();
    api.close();
  });
  testWidgets('单一网卡与助手自动选择，检测未知不假装通过，逐步进入 BIOS', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final api = WakeApi(
        baseUri: () async => Uri.parse('https://example.test'),
        accountToken: () async => 'token');
    final windows = WindowsWakeService(
        api: api,
        storage: const FlutterSecureStorage(),
        run: (_, args) async {
          return ProcessResult(
              1,
              0,
              '{"magicPacket":"Enabled","wakeArmed":true,"shutdownWake":null}',
              '');
        });
    final wake = ScreenWake(windows: windows);
    await wake.bindAccount('user', 'server');
    wake.agents = [
      const WakeAgent(id: 'helper', name: '家中手机', online: true, enabled: true)
    ];
    await tester.pumpWidget(ChangeNotifierProvider<WakeProvider>.value(
        value: wake, child: const MaterialApp(home: WakeSetupScreen())));
    await tester.pumpAndSettle();
    expect(find.text('检测网络唤醒设置'), findsOneWidget);
    expect(find.text('无法自动判断'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('家中手机'), 100);
    expect(find.text('家中手机'), findsOneWidget);
    expect(find.text('开启主板网络唤醒'), findsNothing);
    await tester.scrollUntilVisible(find.text('下一步').hitTestable(), 150);
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('开启主板网络唤醒'), findsOneWidget);
    expect(find.text('保存并开始测试'), findsNothing);
    wake.replaceAgents([
      const WakeAgent(id: 'other', name: '另一台手机', online: true, enabled: true)
    ]);
    await tester.scrollUntilVisible(find.text('上一步').hitTestable(), 150);
    await tester.tap(find.text('上一步'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('下一步').hitTestable(), 150);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '下一步'))
            .onPressed,
        isNull);
    expect(find.text('请选择家中手机'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    wake.dispose();
    api.close();
  });
  testWidgets('离线助手禁用开机，发送状态不显示电脑已上线', (tester) async {
    final wake = ScreenWake();
    await wake.bindAccount('user', 'server');
    wake.targets = [
      const WakeTarget(
          id: 'pc',
          name: '家中电脑',
          deviceId: '123',
          mac: '02:11:22:33:44:55',
          agentId: 'phone',
          online: false,
          agentOnline: false,
          revision: 1)
    ];
    wake.history = {
      'pc': [
        const WakeRequest(
            id: 'r', targetId: 'pc', phase: WakePhase.sent, createdAtMs: 1)
      ]
    };
    await tester.pumpWidget(ChangeNotifierProvider<WakeProvider>.value(
        value: wake, child: const MaterialApp(home: WakeScreen())));
    await tester.pump();
    expect(find.text('信号已发送，等待电脑上线'), findsOneWidget);
    expect(find.text('电脑已上线'), findsNothing);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.textContaining('领取：未收到'), findsOneWidget);
    expect(find.textContaining('发送回执：未收到'), findsOneWidget);
    expect(find.textContaining('电脑上线：未收到'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    final button =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '正在开机…'));
    expect(button.onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
    wake.dispose();
  });
  testWidgets('未登录入口要求登录，不显示开机按钮', (tester) async {
    final wake = ScreenWake();
    await tester.pumpWidget(ChangeNotifierProvider<WakeProvider>.value(
        value: wake, child: const MaterialApp(home: WakeScreen())));
    expect(find.text('登录后配置远程开机'), findsOneWidget);
    expect(find.text('开机'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    wake.dispose();
  });
}
