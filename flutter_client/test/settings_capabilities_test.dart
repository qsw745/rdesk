import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rdesk/app.dart';
import 'package:rdesk/src/utils/router.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('Windows 安全设置没有本机被控和移动权限选项', (tester) async {
    appRouter.go('/settings?section=security');
    await tester.pumpWidget(const RDeskApp());
    await tester.pumpAndSettle();
    expect(find.text('永久密码'), findsNothing);
    expect(find.text('无人值守模式'), findsNothing);
    expect(find.text('自动同步剪贴板'), findsOneWidget);
    expect(find.text('移动被控'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  testWidgets('Mac 常规设置保留真实桌面被控入口', (tester) async {
    appRouter.go('/settings');
    await tester.pumpWidget(const RDeskApp());
    await tester.pumpAndSettle();
    expect(find.text('桌面被控端'), findsOneWidget);
    expect(find.text('移动被控'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
