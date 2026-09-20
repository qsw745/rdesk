import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rdesk/src/models/wake_pairing.dart';
import 'package:rdesk/src/providers/wake_provider.dart';
import 'package:rdesk/src/services/pairing_scan_camera.dart';
import 'package:rdesk/src/screens/wake_pairing_scan_screen.dart';
import 'wake_pairing_test.dart' show PairApi;
import 'wake_provider_test.dart' show TestAgent;

class TestCamera implements PairingScanCamera {
  int starts = 0, stops = 0, disposals = 0;
  bool denied = false;
  ValueChanged<String>? callback;
  @override
  bool get canResume => !denied && starts > 0;
  @override
  Future<void> start() async {
    starts++;
    if (denied) throw StateError('denied');
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }

  @override
  Widget preview(ValueChanged<String> onCode) {
    callback = onCode;
    return const SizedBox();
  }
}

class ScanApi extends PairApi {
  int resolves = 0;
  Completer<Map<String, dynamic>>? resolveBarrier;
  @override
  Future<Map<String, dynamic>> resolvePairing(WakePairingCode code) async {
    resolves++;
    return resolveBarrier?.future ??
        Future.value({
          'id': 'a' * 32,
          'name': '书房电脑',
          'device_id': 'pc',
          'state': 'pending',
          'expires_at_ms': DateTime.now().millisecondsSinceEpoch + 300000
        });
  }
}

void main() {
  testWidgets('相机点击才开启，拒绝后仍可输入手动码并先展示确认', (tester) async {
    final api = ScanApi();
    final wake = WakeProvider(api: api, agent: TestAgent());
    await wake.bindAccount('user', 'server');
    final camera = TestCamera()..denied = true;
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: wake,
        child: MaterialApp(home: WakePairingScanScreen(camera: camera))));
    await tester.pumpAndSettle();
    expect(camera.starts, 0);
    await tester.ensureVisible(find.text('开启相机扫码'));
    await tester.tap(find.text('开启相机扫码'));
    await tester.pumpAndSettle();
    expect(camera.starts, 1);
    expect(find.textContaining('无法使用相机'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ABCD EFGH JKLM NPQR');
    await tester.ensureVisible(find.text('使用配对码继续'));
    await tester.tap(find.text('使用配对码继续'));
    await tester.pumpAndSettle();
    expect(api.resolves, 1);
    expect(find.text('确认添加这台电脑'), findsOneWidget);
    expect(api.claims, 0);
    await tester.pumpWidget(const SizedBox());
    expect(camera.disposals, 1);
    wake.dispose();
  });
  testWidgets('拒绝外部 URL，重复扫码只解析一次，退出后停用相机', (tester) async {
    final api = ScanApi()..resolveBarrier = Completer();
    final wake = WakeProvider(api: api, agent: TestAgent());
    await wake.bindAccount('user', 'server');
    final camera = TestCamera();
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: wake,
        child: MaterialApp(home: WakePairingScanScreen(camera: camera))));
    await tester.pumpAndSettle();
    camera.callback!('https://attacker.test');
    await tester.pumpAndSettle();
    expect(api.resolves, 0);
    final text = WakePairingCode.qr('a' * 32, 'b' * 64).qrText;
    camera.callback!(text);
    camera.callback!(text);
    await tester.pump();
    expect(api.resolves, 1);
    await tester.pumpWidget(const SizedBox());
    api.resolveBarrier!.complete({'id': 'a' * 32});
    await tester.pump();
    expect(camera.disposals, 1);
    wake.dispose();
  });
  testWidgets('切后台停止相机，退出账号也立即停止采集', (tester) async {
    final api = ScanApi();
    final wake = WakeProvider(api: api, agent: TestAgent());
    await wake.bindAccount('user', 'server');
    final camera = TestCamera();
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: wake,
        child: MaterialApp(home: WakePairingScanScreen(camera: camera))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('开启相机扫码'));
    await tester.tap(find.text('开启相机扫码'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(camera.stops, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(camera.starts, 2);
    await wake.stopForAccountExit();
    await tester.pump();
    expect(camera.stops, greaterThan(1));
    expect(find.text('登录后扫码'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    wake.dispose();
  });
}
