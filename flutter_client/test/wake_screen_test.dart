import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rdesk/src/models/wake.dart';
import 'package:rdesk/src/providers/wake_provider.dart';
import 'package:rdesk/src/services/wake_api.dart';
import 'package:rdesk/src/screens/wake_screen.dart';
import 'wake_provider_test.dart' show TestAgent;

class ScreenWake extends WakeProvider {
  ScreenWake()
      : super(
            api: WakeApi(
                baseUri: () async => Uri.parse('https://example.test'),
                accountToken: () async => 'token'),
            agent: TestAgent());
  @override
  Future<void> refresh() async {}
}

void main() {
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
    await tester.tap(find.text('查看记录'));
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
