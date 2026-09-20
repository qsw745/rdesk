import 'package:provider/provider.dart';
import 'package:rdesk/src/providers/app_update_provider.dart';
import 'package:rdesk/src/models/app_update.dart';
import 'package:rdesk/src/widgets/app_update_widgets.dart';
import 'app_update_test.dart' show FakeService;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rdesk/app.dart';
import 'package:rdesk/src/utils/router.dart';

void main() {
  testWidgets('关于页面直接提供检查更新和自动检查开关', (tester) async {
    SharedPreferences.setMockInitialValues({'updates.automatic': false});
    await tester.pumpWidget(const RDeskApp());
    await tester.pumpAndSettle();
    appRouter.go('/settings?section=about');
    await tester.pumpAndSettle();
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('自动检查更新'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('更新详情在手机、电脑和大字体下均无溢出', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final update = AppUpdateProvider(
        service: FakeService(),
        installedVersion: () async => AppVersion.parse('2.2.0', 17));
    await update.check(manual: true);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final width in [320.0, 640.0, 1200.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: update,
          child: MaterialApp(
              home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: const Scaffold(
                      body: SingleChildScrollView(child: UpdateCard()))))));
      await tester.pumpAndSettle();
      expect(find.text('下载更新'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'width=$width');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    update.dispose();
  });
}
