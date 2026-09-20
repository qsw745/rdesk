import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rdesk/app.dart';
import 'package:rdesk/src/utils/router.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appRouter.go('/');
  });
  testWidgets('Windows 窄窗口仍使用桌面导航并直达设置', (tester) async {
    tester.view.physicalSize = const Size(640, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const RDeskApp());
    await tester.pumpAndSettle();
    expect(find.text('我的'), findsNothing);
    expect(find.byTooltip('设置'), findsOneWidget);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('常规'), findsOneWidget);
    expect(find.text('安全'), findsOneWidget);
    expect(find.text('网络'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  testWidgets('iPad 宽屏仍使用手机三个主入口', (tester) async {
    tester.view.physicalSize = const Size(1024, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const RDeskApp());
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('设备'), findsOneWidget);
    expect(find.text('协助'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('云设备'), findsNothing);
    expect(find.text('地址簿'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  testWidgets('桌面常用页面在不同宽度和大字体下无溢出', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final width in [640.0, 1024.0, 1440.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        tester.view.physicalSize = Size(width, 900);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pumpWidget(const RDeskApp());
        for (final route in [
          '/',
          '/settings',
          '/settings?section=security',
          '/me',
          '/assist'
        ]) {
          appRouter.go(route);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: '$route width=$width scale=$scale');
        }
      }
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
