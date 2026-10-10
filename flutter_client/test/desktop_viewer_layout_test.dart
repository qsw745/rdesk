import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rdesk/src/models/session.dart';
import 'package:rdesk/src/providers/connection_provider.dart';
import 'package:rdesk/src/providers/session_provider.dart';
import 'package:rdesk/src/providers/settings_provider.dart';
import 'package:rdesk/src/widgets/desktop_viewer_layout.dart';
import 'package:rdesk/src/widgets/hardware_keyboard_forwarder.dart';
import 'package:rdesk/src/widgets/remote_canvas.dart';
import 'package:rdesk/src/widgets/remote_file_drop.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records what the layout asks the session to send. Whether a session may
/// send at all (watching only) is the provider's own rule, tested with it.
class RecordingSession extends SessionProvider {
  final sent = <String>[];

  @override
  Future<bool> sendAction(String sessionId, String action) async {
    sent.add('action:$action');
    return true;
  }

  @override
  Future<bool> sendTextInput(String sessionId, String text) async {
    sent.add('text:$text');
    return true;
  }
}

/// The desktop viewer has its own layout. Keyboard forwarding was once added
/// to the phone layout only and shipped as if desktops had it.
void main() {
  Future<RecordingSession> pump(WidgetTester tester, String peerOs) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = RecordingSession();
    addTearDown(session.dispose);
    session.setSession(SessionInfo(
      sessionId: 's',
      peerId: '123456789',
      peerHostname: 'PC',
      peerOs: peerOs,
      state: SessionState.active,
      connectedAt: DateTime.now(),
    ));
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionProvider>.value(value: session),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => ConnectionProvider()),
      ],
      child: const MaterialApp(home: DesktopViewerLayout(sessionId: 's')),
    ));
    await tester.pump();
    return session;
  }

  testWidgets('桌面端远控界面转发实体键盘，并接受拖入的文件', (tester) async {
    final session = await pump(tester, 'windows');

    final forwarder = tester.widget<HardwareKeyboardForwarder>(
        find.byType(HardwareKeyboardForwarder));
    expect(forwarder.peerOs, 'windows');
    expect(forwarder.enabled, isTrue);
    expect(find.byType(RemoteFileDrop), findsOneWidget);

    session.toggleViewOnly();
    await tester.pump();
    expect(
        tester
            .widget<HardwareKeyboardForwarder>(
                find.byType(HardwareKeyboardForwarder))
            .enabled,
        isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('在桌面端远控界面敲键盘，文字和按键真的发往对方', (tester) async {
    final session = await pump(tester, 'windows');

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH, character: 'h');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(session.sent, ['text:h', 'action:key:enter']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  Future<void> wheel(WidgetTester tester, double dy) async {
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final centre = tester.getCenter(find.byType(RemoteCanvas));
    await tester.sendEventToBinding(pointer.hover(centre));
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await tester.pump();
  }

  // Lets the wheel step pass in real time; the layout reads the wall clock.
  Future<void> nextWheelStep(WidgetTester tester) => tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));

  testWidgets('滚轮滚动对方电脑的内容，方向一致，连续滚动按步发送', (tester) async {
    final session = await pump(tester, 'windows');

    await wheel(tester, -40);
    await wheel(tester, -40);
    await wheel(tester, -40);
    expect(session.sent, ['action:scroll_up']);

    await nextWheelStep(tester);
    await wheel(tester, 40);
    expect(session.sent, ['action:scroll_up', 'action:scroll_down']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('对方是手机时滚轮方向换成手指滑动方向，页面仍朝滚轮方向走', (tester) async {
    final session = await pump(tester, 'android');

    // 手机把 scroll_down 做成手指下滑，页面回到上方——与滚轮向上一致。
    await wheel(tester, -40);
    expect(session.sent, ['action:scroll_down']);

    await nextWheelStep(tester);
    await wheel(tester, 40);
    expect(session.sent, ['action:scroll_down', 'action:scroll_up']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('桌面端侧栏只对做得到的被控端提供重启和关机', (tester) async {
    final session = await pump(tester, 'windows');
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    expect(find.text('重启电脑'), findsOneWidget);
    expect(find.text('关机'), findsOneWidget);

    await tester.tap(find.text('关机'));
    await tester.pumpAndSettle();
    expect(find.textContaining('未保存'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(session.sent, isEmpty);

    await tester.tap(find.text('重启电脑'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '重启'));
    await tester.pump();
    await tester.pump();
    expect(session.sent, ['action:power_restart']);
    expect(find.text('对方电脑已接受，约 10 秒后重启'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Mac 被控端的侧栏没有重启和关机', (tester) async {
    await pump(tester, 'macOS');
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();

    expect(find.text('重启电脑'), findsNothing);
    expect(find.text('关机'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
