import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rdesk/src/models/wake.dart';
import 'package:rdesk/src/providers/wake_provider.dart';
import 'package:rdesk/src/screens/wake_mobile_setup_screen.dart';
import 'wake_pairing_test.dart' show PairApi;
import 'wake_provider_test.dart' show TestAgent;

class SetupWake extends WakeProvider {
  SetupWake() : super(api: PairApi(), agent: TestAgent());
  int completions = 0;
  @override
  Future<void> refresh() async {}
  @override
  void setVisible(bool v) {}
  @override
  Future<bool> completeTarget(String id, String agentId) async {
    completions++;
    return true;
  }

  void helpers(List<WakeAgent> values) {
    agents = values;
    notifyListeners();
  }
}

const target = WakeTarget(
    id: 'pc',
    name: '书房电脑',
    deviceId: 'pc-device',
    mac: '02:11:22:33:44:55',
    agentId: '',
    online: false,
    agentOnline: true,
    revision: 1,
    setupComplete: false);
WakeAgent helper(String id, bool online) =>
    WakeAgent(id: id, name: id, online: online, enabled: true);
void main() {
  testWidgets('单一在线助手预选，离线不换另一台，BIOS 确认前不得完成', (tester) async {
    final wake = SetupWake();
    await wake.bindAccount('user', 'server');
    wake.targets = [target];
    wake.agents = [helper('原助手', true)];
    await tester.pumpWidget(ChangeNotifierProvider<WakeProvider>.value(
        value: wake,
        child: const MaterialApp(home: WakeMobileSetupScreen(targetId: 'pc'))));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '下一步'))
            .onPressed,
        isNotNull);
    expect(wake.completions, 0);
    wake.helpers([helper('原助手', false), helper('另一个助手', true)]);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<RadioListTile<String>>(
                find.widgetWithText(RadioListTile<String>, '原助手'))
            .groupValue,
        '原助手');
    await tester.ensureVisible(find.text('下一步'));
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存，进入测试'))
            .onPressed,
        isNull);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存，进入测试'));
    await tester.tap(find.text('保存，进入测试'));
    await tester.pumpAndSettle();
    expect(wake.completions, 1);
    expect(find.text('电脑已上线'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    wake.dispose();
  });
  testWidgets('多台助手不擅自选择，没有助手保留草稿提示', (tester) async {
    final wake = SetupWake();
    await wake.bindAccount('user', 'server');
    wake.targets = [target];
    wake.agents = [helper('a', true), helper('b', true)];
    await tester.pumpWidget(ChangeNotifierProvider<WakeProvider>.value(
        value: wake,
        child: const MaterialApp(home: WakeMobileSetupScreen(targetId: 'pc'))));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '下一步'))
            .onPressed,
        isNull);
    wake.helpers([]);
    await tester.pumpAndSettle();
    expect(find.textContaining('尚无家中助手'), findsOneWidget);
    expect(wake.completions, 0);
    await tester.pumpWidget(const SizedBox());
    wake.dispose();
  });
}
