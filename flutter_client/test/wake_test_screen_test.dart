import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rdesk/src/models/wake.dart';
import 'package:rdesk/src/providers/wake_provider.dart';
import 'package:rdesk/src/screens/wake_test_screen.dart';
import 'wake_screen_test.dart' show ScreenWake;

void main() {
  testWidgets('测试页显示领取发包证据且离线助手阻止发送', (tester) async {
    final wake = ScreenWake();
    await wake.bindAccount('u', 'server');
    wake.targets = [
      const WakeTarget(
          id: 'target',
          name: '测试电脑',
          deviceId: 'd',
          mac: '02:11:22:33:44:55',
          agentId: 'agent',
          online: false,
          agentOnline: false,
          revision: 1)
    ];
    wake.history = {
      'target': [
        const WakeRequest(
            id: 'request-one',
            targetId: 'target',
            phase: WakePhase.unconfirmed,
            createdAtMs: 1000,
            sentAtMs: 2000)
      ]
    };
    await tester.pumpWidget(ChangeNotifierProvider<WakeProvider>.value(
        value: wake,
        child: const MaterialApp(home: WakeTestScreen(targetId: 'target'))));
    await tester.pump();
    expect(find.textContaining('停在登录界面'), findsOneWidget);
    final button = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '发送测试开机指令'));
    expect(button.onPressed, isNull);
    await wake.bindAccount('other', 'server');
    await tester.pump();
    expect(find.text('账号或服务器已变更，请返回。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    wake.dispose();
  });
}
