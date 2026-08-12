import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rdesk/src/providers/session_provider.dart';
import 'package:rdesk/src/widgets/remote_canvas.dart';

/// 1×1 透明 PNG，只为让画布进入「有帧」分支。
final _pngFrame = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8AAAAMBAQ'
  'DJ/pLvAAAAAElFTkSuQmCC',
);

Future<SessionProvider> _pumpCanvas(
  WidgetTester tester, {
  required bool pointerMode,
  int quarterTurns = 0,
  void Function(Offset position)? onRemoteTap,
  void Function(Offset position)? onRemoteLongPress,
}) async {
  final provider = SessionProvider();
  addTearDown(provider.dispose);
  provider.updateFrame(_pngFrame, 1080, 2400);
  if (pointerMode) provider.togglePointerMode();
  for (var i = 0; i < quarterTurns; i++) {
    provider.rotateCanvas();
  }

  await tester.pumpWidget(
    ChangeNotifierProvider<SessionProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: RemoteCanvas(
            sessionId: 's',
            enableZoom: true,
            onRemoteTap: (position) async => onRemoteTap?.call(position),
            onRemoteLongPress: (position) async =>
                onRemoteLongPress?.call(position),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return provider;
}

void main() {
  testWidgets('指针模式挂载虚拟指针按钮组', (tester) async {
    await _pumpCanvas(tester, pointerMode: true);

    expect(find.text('点击'), findsOneWidget);
    expect(find.text('长按'), findsOneWidget);
    expect(find.text('拖拽'), findsOneWidget);
  });

  testWidgets('关闭指针模式时不显示按钮组', (tester) async {
    await _pumpCanvas(tester, pointerMode: false);

    expect(find.text('点击'), findsNothing);
    expect(find.text('拖拽'), findsNothing);
  });

  testWidgets('点击按钮把落点发到指针位置，而不是按钮位置', (tester) async {
    final taps = <Offset>[];
    await _pumpCanvas(
      tester,
      pointerMode: true,
      onRemoteTap: taps.add,
    );

    await tester.tap(find.text('点击'));
    await tester.pump();

    // 指针初始停在画面正中。
    expect(taps, [const Offset(0.5, 0.5)]);
  });

  testWidgets('长按按钮走长按通道', (tester) async {
    final longPresses = <Offset>[];
    await _pumpCanvas(
      tester,
      pointerMode: true,
      onRemoteLongPress: longPresses.add,
    );

    await tester.tap(find.text('长按'));
    await tester.pump();

    expect(longPresses, [const Offset(0.5, 0.5)]);
  });

  testWidgets('挂载后再开指针模式也能生效', (tester) async {
    final provider = await _pumpCanvas(tester, pointerMode: false);
    expect(find.text('点击'), findsNothing);

    provider.togglePointerMode();
    await tester.pump();

    expect(find.text('点击'), findsOneWidget);
  });

  testWidgets('旋转 90° 后画布仍然正常构建', (tester) async {
    final provider = await _pumpCanvas(
      tester,
      pointerMode: true,
      quarterTurns: 1,
    );

    expect(provider.rotationQuarterTurns, 1);
    expect(tester.takeException(), isNull);
    expect(find.text('点击'), findsOneWidget);
  });
}
