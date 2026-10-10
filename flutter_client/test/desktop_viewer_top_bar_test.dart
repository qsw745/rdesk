import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rdesk/src/models/remote_display.dart';
import 'package:rdesk/src/models/session.dart';
import 'package:rdesk/src/providers/session_provider.dart';
import 'package:rdesk/src/utils/theme.dart';
import 'package:rdesk/src/widgets/desktop_viewer_top_bar.dart';

void main() {
  testWidgets('窗口很窄、屏幕很多时顶栏不溢出，计时和控制中心仍在', (tester) async {
    tester.view.physicalSize = const Size(520, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = SessionProvider(
      fetchDisplays: (_) async => const [
        RemoteDisplay(index: 0, title: '显示屏 1', model: 'VG27AQL3A'),
        RemoteDisplay(
            index: 1, title: '显示屏 2', model: 'Built-in Retina Display'),
        RemoteDisplay(index: 2, title: '显示屏 3', model: 'DELL U2723QE'),
        RemoteDisplay(index: 3, title: '显示屏 4', width: 1920, height: 1080),
      ],
      switchMonitor: (_, __) async => true,
    );
    addTearDown(session.dispose);
    session.setSession(SessionInfo(
      sessionId: 's',
      peerId: '123456789',
      peerHostname: 'Mac',
      peerOs: 'macos',
      state: SessionState.active,
      connectedAt: DateTime.now(),
    ));

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: session,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Column(children: [
            DesktopViewerTopBar(
                sessionId: 's', isSidebarOpen: true, onToggleSidebar: () {}),
          ]),
        ),
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('显示屏 1'), findsOneWidget);
    expect(find.text('控制中心'), findsOneWidget);
    // 放不下的标签可以横向滚动出来。
    await tester.scrollUntilVisible(find.text('显示屏 4'), 80,
        scrollable: find.byType(Scrollable).first);
    expect(tester.getRect(find.text('显示屏 4')).right,
        lessThanOrEqualTo(tester.getRect(find.text('控制中心')).left));
  });
}
