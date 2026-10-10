import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rdesk/src/providers/session_provider.dart';
import 'package:rdesk/src/services/rdesk_bridge_service.dart';
import 'package:rdesk/src/utils/theme.dart';
import 'package:rdesk/src/utils/windows_ui_font.dart';
import 'package:rdesk/src/widgets/remote_file_drop.dart';

void main() {
  final sent = <String>[];
  var outcome = FileSendOutcome.saved;

  Future<SessionProvider> pump(WidgetTester tester) async {
    sent.clear();
    final session = SessionProvider();
    addTearDown(session.dispose);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: session,
      child: MaterialApp(
        home: Scaffold(
          body: RemoteFileDrop(
            sessionId: 's',
            send: (sessionId, path) async {
              sent.add(path);
              return FileSendResult(outcome, savedAs: 'a (1).txt');
            },
            child: const SizedBox.expand(),
          ),
        ),
      ),
    ));
    return session;
  }

  RemoteFileDropState state(WidgetTester tester) =>
      tester.state<RemoteFileDropState>(find.byType(RemoteFileDrop));

  testWidgets('拖入的文件逐个发送，并说明对方保存成了什么名字', (tester) async {
    outcome = FileSendOutcome.saved;
    await pump(tester);

    await state(tester).sendFiles(['/tmp/a.txt', r'C:\x\b.pdf']);
    await tester.pump();

    expect(sent, ['/tmp/a.txt', r'C:\x\b.pdf']);
    expect(find.textContaining('已保存到对方电脑的「下载」文件夹'), findsOneWidget);
    expect(find.textContaining('a (1).txt'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('发送失败时如实说明原因，不显示已保存', (tester) async {
    outcome = FileSendOutcome.tooLarge;
    await pump(tester);

    await state(tester).sendFiles(['/tmp/big.iso']);
    await tester.pump();

    expect(find.textContaining('太大'), findsOneWidget);
    expect(find.textContaining('已保存'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('仅观看时不发送文件', (tester) async {
    final session = await pump(tester);
    session.toggleViewOnly();

    await state(tester).sendFiles(['/tmp/a.txt']);
    await tester.pump();

    expect(sent, isEmpty);
    expect(find.textContaining('仅观看'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  test('每种发送结果都有给人看的说明，只有确认保存才算成功', () {
    for (final value in FileSendOutcome.values) {
      final result = FileSendResult(value);
      expect(result.describe('x.txt'), isNotEmpty);
      expect(result.saved, value == FileSendOutcome.saved);
    }
  });

  testWidgets('Windows 加载到界面字体后主题使用它，否则沿用系统字体', (tester) async {
    addTearDown(() => WindowsUiFont.debugLoaded = false);

    WindowsUiFont.debugLoaded = false;
    expect(AppTheme.lightTheme.textTheme.titleLarge!.fontFamily,
        'Microsoft YaHei UI');

    WindowsUiFont.debugLoaded = true;
    expect(AppTheme.lightTheme.textTheme.titleLarge!.fontFamily,
        WindowsUiFont.family);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
