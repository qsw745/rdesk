import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rdesk/src/models/remote_display.dart';
import 'package:rdesk/src/models/session.dart';
import 'package:rdesk/src/providers/session_provider.dart';
import 'package:rdesk/src/utils/theme.dart';
import 'package:rdesk/src/widgets/remote_display_tabs.dart';

const _two = [
  RemoteDisplay(
      index: 0,
      title: '显示屏 1',
      model: 'VG27AQL3A',
      width: 2560,
      height: 1440,
      isMain: true),
  RemoteDisplay(
      index: 1,
      title: '显示屏 2',
      model: 'Built-in Retina Display',
      width: 1728,
      height: 1117),
];

void main() {
  late List<String> switched;
  Completer<bool>? answer;

  Future<SessionProvider> pump(
    WidgetTester tester,
    List<RemoteDisplay> displays, {
    double width = 900,
    double textScale = 1,
    ThemeData? theme,
  }) async {
    switched = [];
    answer = null;
    tester.view.physicalSize = Size(width, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = SessionProvider(
      fetchDisplays: (_) async => displays,
      switchMonitor: (_, action) {
        switched.add(action);
        return (answer = Completer<bool>()).future;
      },
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
        theme: theme ?? AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: RemoteDisplayTabs(),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    return session;
  }

  bool selected(WidgetTester tester, String label) => tester
      .getSemantics(find.bySemanticsLabel(label))
      .flagsCollection
      .isSelected
      .toBoolOrNull() ==
      true;

  testWidgets('对方有两块屏幕时两个标签都出现，带各自的型号', (tester) async {
    await pump(tester, _two);

    expect(find.text('显示屏 1'), findsOneWidget);
    expect(find.text('VG27AQL3A'), findsOneWidget);
    expect(find.text('显示屏 2'), findsOneWidget);
    expect(find.text('Built-in Retina Display'), findsOneWidget);
    expect(selected(tester, '显示屏 1（VG27AQL3A）'), isTrue);
    expect(selected(tester, '显示屏 2（Built-in Retina Display）'), isFalse);
    // 以前每个标签上有一个点了没反应的关闭图标。
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('点另一块屏幕：等待对方时显示进度，确认后选中它', (tester) async {
    await pump(tester, _two);

    await tester.tap(find.text('显示屏 2'));
    await tester.pump();
    expect(switched, ['switch_monitor_1']);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // 等待期间再点不会重复发送。
    await tester.tap(find.text('显示屏 1'));
    await tester.pump();
    expect(switched, hasLength(1));

    answer!.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(selected(tester, '显示屏 2（Built-in Retina Display）'), isTrue);
  });

  testWidgets('对方没有切换时说明原因，选中的仍是原来那块屏幕', (tester) async {
    await pump(tester, _two);

    await tester.tap(find.text('显示屏 2'));
    await tester.pump();
    answer!.complete(false);
    await tester.pump();
    await tester.pump();

    expect(find.text('没有切换到显示屏 2，对方电脑没有响应'), findsOneWidget);
    expect(selected(tester, '显示屏 1（VG27AQL3A）'), isTrue);
  });

  testWidgets('读屏和开关控制也能切换屏幕', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, _two);

    tester.semantics.tap(find.semantics.byLabel('显示屏 2（Built-in Retina Display）'));
    await tester.pump();

    expect(switched, ['switch_monitor_1']);
    answer!.complete(true);
    await tester.pumpAndSettle();
    handle.dispose();
  });

  testWidgets('系统文字放大两倍时标签里的字不会被裁掉', (tester) async {
    await pump(tester, _two, textScale: 2);

    final strip = tester.getSize(find.byType(RemoteDisplayTabs));
    final title = tester.getSize(find.text('显示屏 1'));
    expect(title.height, lessThanOrEqualTo(strip.height - 6));
  });

  testWidgets('只有一块屏幕时标签不可点，也不发切换指令', (tester) async {
    await pump(tester, const [RemoteDisplay(index: 0, title: '显示屏 1')]);

    await tester.tap(find.text('显示屏 1'));
    await tester.pump();

    expect(switched, isEmpty);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('窗口很窄、字体放大两倍、深色主题下也不溢出', (tester) async {
    await pump(
      tester,
      const [
        ..._two,
        RemoteDisplay(index: 2, title: '显示屏 3', model: 'A very long monitor model name 34WQ75C-B'),
      ],
      width: 360,
      textScale: 2,
      theme: AppTheme.darkTheme,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('显示屏 3'), findsOneWidget);
  });
}
