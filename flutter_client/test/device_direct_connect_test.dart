import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rdesk/src/models/account.dart';
import 'package:rdesk/src/models/address_book.dart';
import 'package:rdesk/src/models/session.dart';
import 'package:rdesk/src/providers/auth_provider.dart';
import 'package:rdesk/src/providers/address_book_provider.dart';
import 'package:rdesk/src/providers/connection_provider.dart';
import 'package:rdesk/src/providers/settings_provider.dart';
import 'package:rdesk/src/providers/session_provider.dart';
import 'package:rdesk/src/providers/wake_provider.dart';
import 'package:rdesk/src/services/wake_api.dart';
import 'package:rdesk/src/services/wake_agent_channel.dart';
import 'package:rdesk/src/screens/my_devices_screen.dart';
import 'package:rdesk/src/utils/theme.dart';

class AccountFake extends AuthProvider {
  AccountSession? value = const AccountSession(
      token: 'test-token',
      userId: 'owner',
      username: 'owner',
      displayName: 'owner');
  List<AccountDevice> rows = [
    const AccountDevice(
        deviceId: '123456789',
        hostname: '家中电脑',
        platform: 'macos',
        updatedAtMs: 0)
  ];
  @override
  AccountSession? get session => value;
  @override
  bool get isLoggedIn => value != null;
  @override
  List<AccountDevice> get devices => value == null ? [] : rows;
  @override
  String? get devicesEndpoint => 'https://qisw.top';
  @override
  Future<void> refreshDevices({bool notifyOnStart = true}) async {}
  void exitAccount() {
    value = null;
    notifyListeners();
  }
}

class ConnectionFake extends ConnectionProvider {
  final calls = <String>[];
  final passwords = <String>[];
  final directCalls = <String>[];
  final disconnected = <String>[];
  String? trusted;
  String? failure;
  Completer<String?>? pending;
  @override
  Future<String?> connect(String id, String password) async {
    calls.add(id);
    passwords.add(password);
    return pending != null
        ? await pending!.future
        : failure == null
            ? 'session-test'
            : null;
  }

  @override
  Future<String?> connectDirectIp(String address, {String? password}) async {
    directCalls.add(address);
    passwords.add(password ?? '');
    return 'direct-session';
  }

  @override
  String? get errorMessage => failure;
  @override
  Future<String?> getTrustedPassword(String id) async => trusted;
  @override
  Future<void> disconnect(String id) async {
    disconnected.add(id);
  }

  @override
  String? peerPlatformForSession(String id) => 'macos';
}

class SessionFake extends SessionProvider {
  SessionInfo? connected;
  @override
  void setSession(SessionInfo session, {String? accessPassword}) {
    connected = session;
  }
}

class SettingsFake extends SettingsProvider {
  String endpoint = 'https://qisw.top';
  @override
  String get signalingServer => endpoint;
  void switchServer() {
    endpoint = 'https://other.test';
    notifyListeners();
  }
}

class BookFake extends AddressBookProvider {
  List<AddressBookEntry> rows = [];
  @override
  List<AddressBookEntry> get allEntries => rows;
}

class WakeFake extends WakeProvider {
  WakeFake()
      : super(
            api: WakeApi(
                baseUri: () async => Uri.parse('https://qisw.top'),
                accountToken: () async => null),
            agent: WakeAgentChannel());
  @override
  Future<void> refresh() async {}
}

void main() {
  late AccountFake auth;
  late ConnectionFake connection;
  late SessionFake session;
  late SettingsFake settings;
  late BookFake book;
  late GoRouter router;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    auth = AccountFake();
    connection = ConnectionFake();
    session = SessionFake();
    settings = SettingsFake();
    book = BookFake();
  });
  Future<void> show(WidgetTester tester,
      {ThemeData? theme, double scale = 1}) async {
    router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const MyDevicesScreen()),
      GoRoute(
          path: '/remote/:id',
          builder: (_, __) => const Scaffold(body: Text('远控画面'))),
      GoRoute(
          path: '/assist',
          builder: (_, __) => const Scaffold(body: Text('不应跳到远程协助'))),
    ]);
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<ConnectionProvider>.value(value: connection),
          ChangeNotifierProvider<SessionProvider>.value(value: session),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<AddressBookProvider>.value(value: book),
          ChangeNotifierProvider<WakeProvider>(create: (_) => WakeFake()),
        ],
        child: MaterialApp.router(
            theme: theme ?? AppTheme.lightTheme,
            routerConfig: router,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!))));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    });
  }

  testWidgets('同账号卡片直接连接且不发送旧密码、不经过协助页', (tester) async {
    connection.trusted = 'stale-password';
    await show(tester);
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();
    expect(connection.calls, ['123456789']);
    expect(connection.passwords, ['']);
    expect(session.connected?.peerHostname, '家中电脑');
    expect(find.text('远控画面'), findsOneWidget);
    expect(find.text('不应跳到远程协助'), findsNothing);
  });
  testWidgets('取消连接后迟到成功会断开，不打开远控', (tester) async {
    connection.pending = Completer<String?>();
    await show(tester);
    await tester.tap(find.text('连接'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    connection.pending!.complete('late-session');
    await tester.pumpAndSettle();
    expect(connection.disconnected, ['late-session']);
    expect(session.connected, null);
    expect(find.text('我的设备'), findsOneWidget);
  });
  for (final changeAccount in [true, false]) {
    testWidgets('${changeAccount ? '退出账号' : '切换服务器'}阻止迟到会话', (tester) async {
      connection.pending = Completer<String?>();
      await show(tester);
      await tester.tap(find.text('连接'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      if (changeAccount) {
        auth.exitAccount();
      } else {
        settings.switchServer();
      }
      await tester.pump();
      connection.pending!.complete('stale');
      await tester.pumpAndSettle();
      expect(connection.disconnected, ['stale']);
      expect(session.connected, null);
    });
  }
  testWidgets('失败停留设备页，提示实际原因并可重试', (tester) async {
    connection.failure = '设备离线';
    await show(tester);
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();
    expect(find.text('设备离线'), findsOneWidget);
    expect(session.connected, null);
    connection.failure = null;
    await tester.tap(find.widgetWithText(FilledButton, '连接').last);
    await tester.pumpAndSettle();
    expect(find.text('远控画面'), findsOneWidget);
  });
  testWidgets('旧记录先确认当前服务器，不自动发送缓存密码', (tester) async {
    auth.value = null;
    connection.trusted = 'cached';
    book.rows = [
      AddressBookEntry(
          deviceId: '123456789', alias: '旧电脑', createdAt: DateTime(2026))
    ];
    await show(tester);
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();
    expect(connection.calls, isEmpty);
    expect(find.textContaining('旧记录未保存服务器'), findsOneWidget);
    await tester.tap(find.text('确认并连接'));
    await tester.pumpAndSettle();
    expect(connection.passwords, ['']);
    expect(find.text('远控画面'), findsOneWidget);
  });
  testWidgets('已知来源的非账号记录也不自动发送未隔离的缓存密码', (tester) async {
    auth.value = null;
    connection.trusted = 'different-server-secret';
    book.rows = [
      AddressBookEntry(
          deviceId: '123456789',
          alias: '收藏电脑',
          endpointScope: 'https://qisw.top',
          createdAt: DateTime(2026))
    ];
    await show(tester);
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();
    expect(connection.calls, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '连接').last);
    await tester.pumpAndSettle();
    expect(connection.passwords, ['']);
  });
  testWidgets('IP收藏保留直连路径，不误当9位设备ID', (tester) async {
    auth.value = null;
    book.rows = [
      AddressBookEntry(
          deviceId: '192.168.1.10:21116',
          alias: '局域网电脑',
          endpointScope: 'http://192.168.1.10:21116',
          createdAt: DateTime(2026))
    ];
    await show(tester);
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();
    expect(connection.calls, isEmpty);
    await tester.enterText(find.byType(TextField).last, 'direct-password');
    await tester.tap(find.widgetWithText(FilledButton, '连接').last);
    await tester.pumpAndSettle();
    expect(connection.directCalls, ['192.168.1.10:21116']);
    expect(connection.passwords, ['direct-password']);
    expect(find.text('远控画面'), findsOneWidget);
  });
  testWidgets('其他服务器的记录不发起连接', (tester) async {
    auth.value = null;
    book.rows = [
      AddressBookEntry(
          deviceId: '123456789',
          alias: '异地电脑',
          endpointScope: 'https://other.test',
          createdAt: DateTime(2026))
    ];
    await show(tester);
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();
    expect(connection.calls, isEmpty);
    expect(find.textContaining('属于另一台服务器'), findsOneWidget);
  });
  testWidgets('Windows在线不会显示不支持的远控按钮', (tester) async {
    auth.rows = [
      const AccountDevice(
          deviceId: '123456789',
          hostname: 'Windows',
          platform: 'windows',
          updatedAtMs: 0)
    ];
    await show(tester);
    expect(find.text('连接'), findsNothing);
    expect(find.text('支持远程开机 · 暂不支持被远控'), findsOneWidget);
  });
  for (final dark in [false, true]) {
    testWidgets('全局 FilterChip ${dark ? '深色' : '浅色'}选中与未选中文字可读',
        (tester) async {
      final theme = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
              body: Row(children: [
            FilterChip(
                label: const Text('分组一'), selected: true, onSelected: (_) {}),
            FilterChip(
                label: const Text('分组二'), selected: false, onSelected: (_) {}),
          ]))));
      for (final selected in [false, true]) {
        final label = find.text(selected ? '分组一' : '分组二');
        final color = DefaultTextStyle.of(tester.element(label)).style.color!;
        final bg = selected
            ? theme.chipTheme.selectedColor!
            : theme.chipTheme.backgroundColor!;
        final a = color.computeLuminance(), b = bg.computeLuminance();
        expect(a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05),
            greaterThanOrEqualTo(4.5));
      }
    });
  }
  for (final dark in [false, true]) {
    testWidgets('${dark ? '深' : '浅'}色筛选标签实际渲染对比度足够，大字号窄屏无溢出', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final theme = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
      await show(tester, theme: theme, scale: 1.6);
      for (final label in ['全部', '在线', '收藏']) {
        final text = find.text(label).first;
        final color = DefaultTextStyle.of(tester.element(text)).style.color!;
        final bg = label == '全部'
            ? theme.chipTheme.secondarySelectedColor!
            : theme.chipTheme.backgroundColor!;
        final a = color.computeLuminance(), b = bg.computeLuminance();
        final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
        expect(ratio, greaterThanOrEqualTo(4.5),
            reason: '$label: $color on $bg');
      }
      expect(tester.takeException(), null);
    });
  }
}
