import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rdesk/src/providers/session_provider.dart';
import 'package:rdesk/src/widgets/remote_control_panel.dart';
import 'package:rdesk/src/widgets/remote_session_tools.dart';

void main() {
  Future<SessionProvider> openActionSheet(
    WidgetTester tester, {
    Size viewport = const Size(390, 844),
    Future<void> Function(String action)? onRemoteAction,
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
                      onRemoteAction: onRemoteAction ?? (_) async {},
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
              onRemoteAction: (action) async => actions.add(action),
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
              onRemoteAction: (_) async {},
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
                onDisconnect: () {},
                onFileManager: () {},
                onToggleToolbar: () {},
                onRemoteAction: (_) async {},
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
              onRemoteAction: (_) async {},
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
              onRemoteAction: (_) async {},
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
