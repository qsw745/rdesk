import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:rdesk/app.dart';
import 'package:rdesk/src/models/account.dart';
import 'package:rdesk/src/models/device.dart';
import 'package:rdesk/src/models/connection_info.dart';
import 'package:rdesk/src/models/wake.dart';
import 'package:rdesk/src/providers/auth_provider.dart';
import 'package:rdesk/src/providers/address_book_provider.dart';
import 'package:rdesk/src/providers/connection_provider.dart';
import 'package:rdesk/src/providers/wake_provider.dart';
import 'package:rdesk/src/utils/device_directory.dart';
import 'package:rdesk/src/ui/device_actions.dart';
import 'package:rdesk/src/utils/router.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appRouter.go('/');
  });
  testWidgets('设备页直接提供统一筛选与添加入口', (tester) async {
    await tester.pumpWidget(const RDeskApp());
    await tester.pumpAndSettle();
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('在线'), findsOneWidget);
    expect(find.text('收藏'), findsWidgets);
    expect(find.byTooltip('添加设备'), findsOneWidget);
  });
  testWidgets('未登录时仍能查看旧收藏，且不冒充在线设备', (tester) async {
    SharedPreferences.setMockInitialValues({
      'address_book_entries': jsonEncode([
        {'deviceId': '123456789', 'alias': '旧的书房电脑', 'createdAt': 0}
      ])
    });
    await tester.pumpWidget(const RDeskApp());
    await tester.pumpAndSettle();
    expect(find.text('旧的书房电脑'), findsOneWidget);
    expect(find.text('按设备码连接'), findsOneWidget);
    expect(find.textContaining('在线 ·'), findsNothing);
    await tester.tap(find.text('旧的书房电脑'));
    await tester.pumpAndSettle();
    expect(find.textContaining('来源未记录'), findsOneWidget);
    appRouter.go('/');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '在线'));
    await tester.pumpAndSettle();
    expect(find.text('旧的书房电脑'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '收藏'));
    await tester.pumpAndSettle();
    expect(find.text('旧的书房电脑'), findsOneWidget);
  });

  testWidgets('纯历史记录默认收起，不计入我的设备，可展开访问', (tester) async {
    SharedPreferences.setMockInitialValues({
      'rdesk.connection_logs': jsonEncode([
        {
          'peerId': 'old-android',
          'peerHostname': '家中手机',
          'peerOs': 'android',
          'connectedAt': '2026-10-01T12:00:00Z',
          'connectionType': 'relay',
        }
      ])
    });
    await tester.pumpWidget(const RDeskApp());
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byType(Navigator).first);
    ctx.read<ConnectionProvider>().debugSeed(
        const DeviceInfo(
            deviceId: 'local', os: 'ios', hostname: '本机', version: 'test'),
        'test',
        history: [
          ConnectionRecord(
              peerId: 'old-android',
              peerHostname: '家中手机',
              peerOs: 'android',
              connectedAt: DateTime.utc(2026, 10, 1),
              connectionType: 'relay')
        ]);
    ctx.read<AuthProvider>().debugSeed(
        const AccountSession(
            token: 'test', userId: 'u', username: '测试', displayName: '测试'),
        [
          const AccountDevice(
              deviceId: 'new-android',
              hostname: '家中手机',
              platform: 'android',
              updatedAtMs: 1)
        ],
        endpoint: 'https://qisw.top');
    await tester.pump();
    expect(find.text('共 1 台 · 1 台在线'), findsOneWidget);
    expect(find.text('家中手机'), findsOneWidget);
    expect(find.text('最近连接（1）'), findsOneWidget);
    await tester.tap(find.text('最近连接（1）'));
    await tester.pumpAndSettle();
    expect(find.text('家中手机'), findsNWidgets(2));
    expect(find.text('按设备码连接 · Android'), findsOneWidget);
    await tester.tap(find.text('家中手机').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('来源未记录'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('同网卡新旧Windows只显示一台，在线优先旧开机状态和旧详情地址', (tester) async {
    SharedPreferences.setMockInitialValues({
      'address_book_entries': jsonEncode([
        {
          'deviceId': 'old-pc',
          'endpointScope': 'https://qisw.top',
          'alias': '',
          'platform': 'windows',
          'createdAt': 0
        },
        {
          'deviceId': 'new-pc',
          'endpointScope': 'https://qisw.top',
          'alias': '',
          'platform': 'windows',
          'createdAt': 0
        },
      ])
    });
    await tester.pumpWidget(const RDeskApp());
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byType(Navigator).first);
    final auth = ctx.read<AuthProvider>();
    auth.debugSeed(
        const AccountSession(
            token: 'test', userId: 'u', username: '测试', displayName: '测试'),
        [
          const AccountDevice(
              deviceId: 'new-pc',
              hostname: '书房电脑',
              platform: 'windows',
              updatedAtMs: 2)
        ],
        endpoint: 'https://qisw.top');
    final wake = ctx.read<WakeProvider>();
    wake.bindAccount('u', 'https://qisw.top');
    wake.targets = const [
      WakeTarget(
          id: 'old',
          name: '书房电脑',
          deviceId: 'old-pc',
          mac: '00:11:22:33:44:55',
          agentId: 'helper',
          online: false,
          agentOnline: true,
          revision: 1),
      WakeTarget(
          id: 'new',
          name: '书房电脑',
          deviceId: 'new-pc',
          mac: '00:11:22:33:44:55',
          agentId: 'helper',
          online: false,
          agentOnline: true,
          revision: 1),
    ];
    wake.history['old'] = [
      WakeRequest(
          id: 'request',
          targetId: 'old',
          phase: WakePhase.sent,
          createdAtMs: DateTime.now().millisecondsSinceEpoch)
    ];
    wake.notifyListeners();
    await tester.pump();
    expect(find.text('书房电脑'), findsOneWidget);
    expect(find.text('共 1 台 · 1 台在线'), findsOneWidget);
    expect(find.textContaining('正在开机'), findsNothing);
    expect(find.text('开机中'), findsNothing);
    appRouter.go(
        '/device/${Uri.encodeComponent(deviceDirectoryKey('https://qisw.top', 'old-pc'))}');
    await tester.pumpAndSettle();
    expect(find.text('找不到这台设备'), findsNothing);
    expect(find.text('书房电脑'), findsWidgets);
    expect(find.text('已发出，等待电脑上线'), findsNothing);
    expect(find.text('电脑已上线'), findsOneWidget);
    final book = ctx.read<AddressBookProvider>();
    final entry = mergeDeviceDirectory(
            endpointScope: 'https://qisw.top',
            accountDevices: auth.devices,
            history: [],
            saved: book.allEntries,
            wakeTargets: wake.targets)
        .single;
    expect(entry.favorite, isTrue);
    await toggleFavorite(ctx, entry);
    expect(book.allEntries, isEmpty);
    appRouter.go('/wake');
    await tester.pumpAndSettle();
    expect(find.text('书房电脑'), findsOneWidget);
    expect(find.text('在线'), findsOneWidget);
    expect(find.text('正在开机'), findsNothing);
    expect(find.text('开机中'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
