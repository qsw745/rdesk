import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rdesk/app.dart';
import 'package:rdesk/src/utils/router.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('Windows 安全设置提供被控密码，没有移动权限选项', (tester) async {
    appRouter.go('/settings?section=security');
    await tester.pumpWidget(const RDeskApp());
    await tester.pumpAndSettle();
    expect(find.text('永久密码'), findsOneWidget);
    expect(find.text('自动同步剪贴板'), findsOneWidget);
    expect(find.text('移动被控'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  testWidgets('Windows 被控入口默认关闭，说明限制且不出现 Mac 授权项', (tester) async {
    appRouter.go('/settings');
    await tester.pumpWidget(const RDeskApp());
    await tester.pumpAndSettle();
    expect(find.text('桌面被控端'), findsOneWidget);
    expect(find.text('允许远程控制本机'), findsOneWidget);
    expect(find.textContaining('已关闭'), findsOneWidget);
    expect(find.text('屏幕录制'), findsNothing);
    expect(find.text('辅助功能'), findsNothing);
    expect(find.textContaining('锁屏'), findsWidgets);
    expect(find.textContaining('管理员身份'), findsWidgets);
    expect(find.textContaining('Mac'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  testWidgets('被控关闭时「重启共享服务」不可用，不能借它绕过开关', (tester) async {
    // Tall enough that the diagnostics tile is on screen and tappable.
    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    appRouter.go('/settings');
    await tester.pumpWidget(const RDeskApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('诊断信息'));
    await tester.pumpAndSettle();
    // TextButton.icon builds a private subclass, so match by `is`.
    final restart = tester.widget<TextButton>(find.ancestor(
        of: find.text('重启共享服务'),
        matching: find.byWidgetPredicate((widget) => widget is TextButton)));
    expect(restart.onPressed, isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  testWidgets('Windows 远程协助页提供本机被控开关', (tester) async {
    appRouter.go('/assist');
    await tester.pumpWidget(const RDeskApp());
    await tester.pumpAndSettle();
    expect(find.text('允许远程控制本机'), findsOneWidget);
    expect(find.textContaining('暂不支持被远程控制'), findsNothing);
    expect(find.textContaining('Mac'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  testWidgets('Mac 常规设置保留真实桌面被控入口', (tester) async {
    appRouter.go('/settings');
    await tester.pumpWidget(const RDeskApp());
    await tester.pumpAndSettle();
    expect(find.text('桌面被控端'), findsOneWidget);
    expect(find.text('移动被控'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
