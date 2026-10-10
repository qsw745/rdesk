import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rdesk/src/models/session.dart';
import 'package:rdesk/src/providers/connection_provider.dart';
import 'package:rdesk/src/providers/session_provider.dart';
import 'package:rdesk/src/providers/settings_provider.dart';
import 'package:rdesk/src/widgets/desktop_viewer_layout.dart';
import 'package:rdesk/src/widgets/hardware_keyboard_forwarder.dart';
import 'package:rdesk/src/widgets/remote_file_drop.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The desktop viewer has its own layout. Keyboard forwarding was once added
/// to the phone layout only and shipped as if desktops had it.
void main() {
  Future<SessionProvider> pump(WidgetTester tester, String peerOs) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = SessionProvider();
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
        ChangeNotifierProvider.value(value: session),
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

  testWidgets('桌面端侧栏只对做得到的被控端提供重启和关机', (tester) async {
    await pump(tester, 'windows');
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    expect(find.text('重启电脑'), findsOneWidget);
    expect(find.text('关机'), findsOneWidget);

    await tester.tap(find.text('关机'));
    await tester.pumpAndSettle();
    expect(find.textContaining('未保存'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Mac 被控端的侧栏没有重启和关机', (tester) async {
    await pump(tester, 'macOS');
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();

    expect(find.text('重启电脑'), findsNothing);
    expect(find.text('关机'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
