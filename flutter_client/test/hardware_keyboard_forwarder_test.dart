import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/models/key_mapping.dart';
import 'package:rdesk/src/widgets/hardware_keyboard_forwarder.dart';

void main() {
  final sent = <String>[];

  Future<void> pump(
    WidgetTester tester, {
    String peerOs = 'windows',
    bool enabled = true,
    WindowsKeyMapping mapping = WindowsKeyMapping.defaults,
    Widget child = const SizedBox.expand(),
  }) async {
    sent.clear();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HardwareKeyboardForwarder(
          peerOs: peerOs,
          enabled: enabled,
          mapping: mapping,
          onText: (text) async => sent.add('text:$text'),
          onAction: (action) async => sent.add('action:$action'),
          child: child,
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('打字按文字发送，功能键按按键发送', (tester) async {
    await pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH, character: 'h');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI, character: 'i');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(sent.join('|'), contains('action:key:enter'));
    expect(sent.where((s) => s.startsWith('text:')).map((s) => s.substring(5))
        .join(), 'hi');
    expect(sent.last, 'action:key:enter');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('按住 Command 再按 C，按映射发送组合键', (tester) async {
    await pump(tester,
        mapping: const WindowsKeyMapping(command: RemoteModifier.ctrl));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(sent, ['action:key:ctrl+c']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('仅观看时不发送任何按键', (tester) async {
    await pump(tester, enabled: false);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(sent, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('焦点在输入框里时，按键留给输入框而不是发往远端', (tester) async {
    await pump(tester, child: const Center(child: TextField()));
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(sent, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('被控端做不到的按键不发送，也不拦截', (tester) async {
    await pump(tester, peerOs: 'android');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();

    expect(sent, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
