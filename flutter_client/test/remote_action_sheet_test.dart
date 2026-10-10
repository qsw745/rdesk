import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rdesk/src/models/session.dart';
import 'package:rdesk/src/providers/session_provider.dart';
import 'package:rdesk/src/widgets/remote_control_panel.dart';
import 'package:rdesk/src/widgets/remote_session_tools.dart';

void main() {
  Future<List<String>> pumpControlBar(
    WidgetTester tester, {
    required String peerOs,
  }) async {
    final actions = <String>[];
    final session = SessionProvider();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: session,
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: RemoteControlBar(
                sessionId: 'test-session',
                peerOs: peerOs,
                onDisconnect: () {},
                onFileManager: () {},
                onToggleToolbar: () {},
                onRemoteAction: (action) async => (actions..add(action)).isNotEmpty,
                onPushClipboard: () async {},
                onPullClipboard: () async {},
                autoHideToolbar: false,
                onAutoHideToolbarChanged: (_) {},
                onActionSheetClosed: () {},
                onUserInteraction: () {},
              ),
            ),
          ),
        ),
      ),
    );
    return actions;
  }

  Future<SessionProvider> openActionSheet(
    WidgetTester tester, {
    Size viewport = const Size(390, 844),
    Future<bool> Function(String action)? onRemoteAction,
    VoidCallback? onToggleToolbar,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = viewport;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final session = SessionProvider();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: session,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (_) => RemoteActionSheet(
                      sessionId: 'test-session',
                      onDisconnect: () {},
                      onFileManager: () {},
                      onToggleToolbar: onToggleToolbar ?? () {},
                      onRemoteAction: onRemoteAction ?? (_) async => true,
                      onPushClipboard: () async {},
                      onPullClipboard: () async {},
                    ),
                  ),
                  child: const Text('打开操作'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开操作'));
    await tester.pumpAndSettle();
    return session;
  }

  testWidgets('竖屏操作弹层不超过可视高度的三分之二', (tester) async {
    await openActionSheet(tester);

    final height = tester.getSize(find.byType(RemoteActionSheet)).height;
    expect(height, lessThanOrEqualTo(844 * 0.66));
  });

  testWidgets('操作弹层提供电脑键盘、控制设置和网络状态入口', (tester) async {
    await openActionSheet(tester);

    await tester.drag(
        find.byType(SingleChildScrollView).last, const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(find.text('电脑键盘'), findsOneWidget);
    expect(find.text('控制设置'), findsOneWidget);
    expect(find.text('网络状态'), findsOneWidget);
  });

  testWidgets('电脑键盘把特殊按键发送为远端动作', (tester) async {
    final actions = <String>[];
    final session = SessionProvider();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: session,
        child: MaterialApp(
          home: Scaffold(
            body: RemoteKeyboardSheet(
              peerOs: 'macOS',
              onSendText: (_) async {},
              onRemoteAction: (action) async => (actions..add(action)).isNotEmpty,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('输入法'), findsOneWidget);
    expect(find.text('Esc'), findsOneWidget);
    await tester.tap(find.text('Esc'));
    await tester.pump();
    expect(actions, contains('key_escape'));
  });

  testWidgets('电脑键盘界面提供输入法切换和完整主键区', (tester) async {
    final session = SessionProvider();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: session,
        child: MaterialApp(
          home: Scaffold(
            body: RemoteKeyboardSheet(
              peerOs: 'macOS',
              onSendText: (_) async {},
              onRemoteAction: (_) async => true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('输入法'), findsOneWidget);
    expect(find.text('电脑键盘'), findsOneWidget);
    expect(find.text('Q'), findsOneWidget);
    expect(find.text('Space'), findsOneWidget);
    expect(find.text('Enter'), findsOneWidget);
  });

  testWidgets('底部键盘入口先打开电脑键盘界面而不是旧文本输入框', (tester) async {
    final session = SessionProvider();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: session,
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: RemoteControlBar(
                sessionId: 'test-session',
                peerOs: 'macOS',
                onDisconnect: () {},
                onFileManager: () {},
                onToggleToolbar: () {},
                onRemoteAction: (_) async => true,
                onPushClipboard: () async {},
                onPullClipboard: () async {},
                autoHideToolbar: false,
                onAutoHideToolbarChanged: (_) {},
                onActionSheetClosed: () {},
                onUserInteraction: () {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('键盘'));
    await tester.pumpAndSettle();

    expect(find.text('电脑键盘'), findsOneWidget);
    expect(find.text('Q'), findsOneWidget);
  });

  testWidgets('连接 macOS 时底栏显示电脑动作并发送对应远端指令', (tester) async {
    final actions = await pumpControlBar(tester, peerOs: 'macOS');

    expect(find.text('展开所有窗口'), findsOneWidget);
    expect(find.text('显示桌面'), findsOneWidget);
    expect(find.text('键盘'), findsOneWidget);
    expect(find.text('操作'), findsOneWidget);
    expect(find.text('返回'), findsNothing);
    expect(find.text('主页'), findsNothing);
    expect(find.text('任务'), findsNothing);

    await tester.tap(find.text('展开所有窗口'));
    await tester.tap(find.text('显示桌面'));
    await tester.pump();

    expect(actions, ['show_all_windows', 'show_desktop']);
  });

  testWidgets('连接 Windows 时底栏显示 Windows 动作并发送对应远端指令', (tester) async {
    final actions = await pumpControlBar(tester, peerOs: 'windows');

    expect(find.text('任务视图'), findsOneWidget);
    expect(find.text('显示桌面'), findsOneWidget);
    expect(find.text('展开所有窗口'), findsNothing);
    expect(find.text('返回'), findsNothing);
    expect(find.text('主页'), findsNothing);

    await tester.tap(find.text('任务视图'));
    await tester.tap(find.text('显示桌面'));
    await tester.pump();

    expect(actions, ['task_view', 'show_desktop']);
  });

  testWidgets('darwin 不会因为包含 win 被当成 Windows', (tester) async {
    await pumpControlBar(tester, peerOs: 'darwin');

    expect(find.text('展开所有窗口'), findsOneWidget);
    expect(find.text('任务视图'), findsNothing);
  });

  testWidgets('Windows 被控端启用桌面按键并标注 Windows 快捷组合', (tester) async {
    final actions = <String>[];
    final session = SessionProvider();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: session,
        child: MaterialApp(
          home: Scaffold(
            body: RemoteKeyboardSheet(
              peerOs: 'windows',
              onSendText: (_) async {},
              onRemoteAction: (action) async => (actions..add(action)).isNotEmpty,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Windows 快捷组合'), findsOneWidget);
    expect(find.text('macOS 快捷组合'), findsNothing);
    await tester.tap(find.text('Esc'));
    await tester.pump();
    expect(actions, ['key_escape']);
  });

  void attach(SessionProvider session, String peerOs) => session.setSession(
      SessionInfo(
        sessionId: 'test-session',
        peerId: '123456789',
        peerHostname: 'PC',
        peerOs: peerOs,
        state: SessionState.active,
        connectedAt: DateTime.now(),
      ));

  testWidgets('Windows 被控端提供重启和关机，确认后才发送', (tester) async {
    final actions = <String>[];
    final session = await openActionSheet(tester,
        onRemoteAction: (action) async => (actions..add(action)).isNotEmpty);
    attach(session, 'windows');
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('重启电脑'), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('重启电脑'));
    await tester.pumpAndSettle();
    expect(find.textContaining('未保存'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(actions, isEmpty);

    await tester.tap(find.text('关机'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '关机'));
    await tester.pump();
    await tester.pump();
    expect(actions, ['power_shutdown']);
    expect(find.text('对方电脑已接受，约 10 秒后关机'), findsOneWidget);
  });

  testWidgets('对方没有执行重启时如实提示，不说已发送', (tester) async {
    // 例如对方是不认识这个指令的旧版本。
    final session =
        await openActionSheet(tester, onRemoteAction: (_) async => false);
    attach(session, 'windows');
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('重启电脑'), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('重启电脑'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '重启'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('对方电脑没有重启'), findsOneWidget);
    expect(find.textContaining('已接受'), findsNothing);
    expect(find.textContaining('已发送'), findsNothing);
  });

  testWidgets('仅观看时不提供重启和关机', (tester) async {
    final session = await openActionSheet(tester);
    attach(session, 'windows');
    session.toggleViewOnly();
    await tester.pumpAndSettle();

    expect(find.text('重启电脑'), findsNothing);
    expect(find.text('关机'), findsNothing);
  });

  testWidgets('Mac 和安卓被控端不显示它们做不到的重启和关机', (tester) async {
    for (final peerOs in ['macOS', 'android']) {
      final session = await openActionSheet(tester);
      attach(session, peerOs);
      await tester.pumpAndSettle();

      expect(find.text('重启电脑'), findsNothing, reason: peerOs);
      expect(find.text('关机'), findsNothing, reason: peerOs);
      Navigator.of(tester.element(find.byType(RemoteActionSheet))).pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('连接 Android 时底栏保留移动端导航动作', (tester) async {
    await pumpControlBar(tester, peerOs: 'android');

    expect(find.text('返回'), findsOneWidget);
    expect(find.text('主页'), findsOneWidget);
    expect(find.text('任务'), findsOneWidget);
    expect(find.text('键盘'), findsOneWidget);
    expect(find.text('操作'), findsOneWidget);
    expect(find.text('展开所有窗口'), findsNothing);
    expect(find.text('显示桌面'), findsNothing);
  });

  testWidgets('电脑键盘文字键通过真实文字输入回调发送', (tester) async {
    final sentTexts = <String>[];
    final session = SessionProvider();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: session,
        child: MaterialApp(
          home: Scaffold(
            body: RemoteKeyboardSheet(
              peerOs: 'macOS',
              onSendText: (text) async => sentTexts.add(text),
              onRemoteAction: (_) async => true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Q'));
    await tester.tap(find.text('Space'));
    await tester.pump();
    expect(sentTexts, ['q', ' ']);
  });

  testWidgets('输入法页可发送一段文字而不返回旧弹窗', (tester) async {
    final sentTexts = <String>[];
    final session = SessionProvider();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: session,
        child: MaterialApp(
          home: Scaffold(
            body: RemoteKeyboardSheet(
              peerOs: 'android',
              onSendText: (text) async => sentTexts.add(text),
              onRemoteAction: (_) async => true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('输入法'));
    await tester.pumpAndSettle();
    expect(find.text('输入远端文字'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '测试文本');
    await tester.tap(find.text('发送到远端'));
    await tester.pump();
    expect(sentTexts, ['测试文本']);
  });

  testWidgets('网络状态只展示当前能够取得的会话指标', (tester) async {
    await openActionSheet(tester);

    await tester.drag(
        find.byType(SingleChildScrollView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.tap(find.text('网络状态'));
    await tester.pumpAndSettle();

    expect(find.text('会话状态'), findsOneWidget);
    expect(find.text('画面延迟'), findsOneWidget);
    expect(find.text('帧率上限'), findsOneWidget);
    expect(find.text('远端系统'), findsOneWidget);
    expect(find.text('丢包率'), findsNothing);
    expect(find.text('带宽占用'), findsNothing);
  });

  testWidgets('控制设置集中提供观看端显示行为', (tester) async {
    await openActionSheet(tester);

    await tester.drag(
        find.byType(SingleChildScrollView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.tap(find.text('控制设置'));
    await tester.pumpAndSettle();

    expect(find.text('自动隐藏工具栏'), findsOneWidget);
    expect(find.text('进入全屏'), findsOneWidget);
    expect(find.text('立即隐藏工具栏'), findsOneWidget);
  });

  testWidgets('自动隐藏开关点击后立即更新显示状态', (tester) async {
    final session = SessionProvider();
    addTearDown(session.dispose);
    bool? changedValue;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: session,
        child: MaterialApp(
          home: Scaffold(
            body: RemoteControlSettingsSheet(
              autoHideToolbar: false,
              onAutoHideChanged: (value) => changedValue = value,
              onToggleFullscreen: () {},
              onHideToolbar: () {},
              onRotate: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('自动隐藏工具栏'));
    await tester.pump();

    expect(changedValue, isTrue);
    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches.last.value, isTrue);
  });

  testWidgets('立即隐藏工具栏会同时关闭设置页和操作弹层', (tester) async {
    var hidden = false;
    await openActionSheet(
      tester,
      onToggleToolbar: () => hidden = true,
    );

    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('控制设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('立即隐藏工具栏'));
    await tester.pumpAndSettle();

    expect(hidden, isTrue);
    expect(find.text('退出远控'), findsNothing);
  });
}
