import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rdesk/src/providers/wake_provider.dart';
import 'package:rdesk/src/providers/wake_pairing_provider.dart';
import 'package:rdesk/src/services/windows_wake_service.dart';
import 'package:rdesk/src/screens/windows_wake_screen.dart';
import 'wake_pairing_test.dart' show PairApi,TestVault;
import 'wake_provider_test.dart' show TestAgent;
class DetectWindows extends WindowsWakeService {
  final WindowsAdapterScan result;
  DetectWindows(PairApi api,this.result):super(api:api,storage:const FlutterSecureStorage(),run:(_,__)async=>ProcessResult(0,0,'false',''));
  @override Future<WindowsAdapterScan> scanAdapters() async=>result;
  @override Future<WindowsWakeCheck> inspect(String mac) async=>const WindowsWakeCheck(magicPacket:WakeCheckState.unknown,wakeArmed:WakeCheckState.enabled,shutdownWake:WakeCheckState.unknown);
}
void main(){
  testWidgets('Windows 检测失败单独显示，可复制诊断但不能生成配对码',(tester)async{
    FlutterSecureStorage.setMockInitialValues({});
    final api=PairApi();final pairing=WakePairingProvider(api:api,vault:TestVault());
    final wake=WakeProvider(api:api,agent:TestAgent(),pairing:pairing,windows:DetectWindows(api,const WindowsAdapterScan(AdapterScanState.failed,[],'source=ip_helper;error=5')));
    await wake.bindAccount('user','https://relay.test');
    await tester.pumpWidget(ChangeNotifierProvider.value(value:wake,child:const MaterialApp(home:WindowsWakeScreen())));
    await tester.pumpAndSettle();
    expect(find.textContaining('网卡检测失败'),findsOneWidget);
    expect(find.text('复制诊断'),findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'生成配对二维码')).onPressed,isNull);
    expect(find.text('选择家中助手'),findsNothing);
    await tester.pumpWidget(const SizedBox());wake.dispose();
  });
}
