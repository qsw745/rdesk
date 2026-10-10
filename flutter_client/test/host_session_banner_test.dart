import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rdesk/src/providers/desktop_host_provider.dart';
import 'package:rdesk/src/utils/theme.dart';
import 'package:rdesk/src/widgets/host_session_banner.dart';

class FakeHost extends DesktopHostProvider {
  bool active = false;
  DateTime? since;
  List<HostViewerInfo> viewers = const [];
  int disconnects = 0;

  @override
  bool get remoteAccessActive => active;
  @override
  DateTime? get remoteAccessSince => since;
  @override
  List<HostViewerInfo> get currentViewers => viewers;
  @override
  Future<bool> revokeAccessAndDisconnect() async {
    disconnects++;
    active = false;
    notifyListeners();
    return true;
  }
}

void main() {
  late FakeHost host;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ChangeNotifierProvider<DesktopHostProvider>.value(
      value: host,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: Column(children: [HostSessionBanner()])),
      ),
    ));
  }

  setUp(() => host = FakeHost());
  tearDown(() => host.dispose());

  testWidgets('没有人访问时不占位置', (tester) async {
    await pump(tester);

    expect(find.textContaining('被控'), findsNothing);
    expect(tester.getSize(find.byType(HostSessionBanner)).height, 0);
  });

  testWidgets('被控时显示时长、对方设备，并可以断开', (tester) async {
    host
      ..active = true
      ..since = DateTime.now().subtract(const Duration(seconds: 75))
      ..viewers = [
        HostViewerInfo(
            name: 'qsw的MacBook Pro',
            platform: 'macos',
            since: DateTime.now().subtract(const Duration(seconds: 75))),
      ];
    await pump(tester);

    expect(find.text('本机被控中'), findsOneWidget);
    // Once for the session, once for the device.
    expect(find.textContaining('00:01:1'), findsNWidgets(2));
    expect(find.text('当前有 1 台设备正在控制此电脑'), findsOneWidget);
    expect(find.text('qsw的MacBook Pro'), findsOneWidget);
    expect(find.textContaining('已连接 00:01:1'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('00:01:1'), findsNWidgets(2));

    await tester.tap(find.text('断开所有远控'));
    await tester.pumpAndSettle();

    expect(host.disconnects, 1);
    expect(find.text('本机被控中'), findsNothing);
  });

  testWidgets('对方名称未知时如实显示，不编造设备名', (tester) async {
    host
      ..active = true
      ..since = DateTime.now();
    await pump(tester);

    expect(find.text('本机被控中'), findsOneWidget);
    expect(find.text('有设备正在访问此电脑'), findsOneWidget);
  });
}
