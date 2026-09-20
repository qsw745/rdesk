import 'dart:convert';
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
  testWidgets('设备页直接提供统一筛选与添加入口', (tester) async {
    await tester.pumpWidget(const RDeskApp());
    await tester.pumpAndSettle();
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('在线'), findsOneWidget);
    expect(find.text('收藏'), findsWidgets);
    expect(find.byTooltip('添加设备'), findsOneWidget);
  });
  testWidgets('未登录时仍能查看旧收藏，且不冒充在线设备', (tester) async {
    SharedPreferences.setMockInitialValues({
      'address_book_entries': jsonEncode([
        {'deviceId': '123456789', 'alias': '旧的书房电脑', 'createdAt': 0}
      ])
    });
    await tester.pumpWidget(const RDeskApp());
    await tester.pumpAndSettle();
    expect(find.text('旧的书房电脑'), findsOneWidget);
    expect(find.textContaining('来源未记录'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '在线'));
    await tester.pumpAndSettle();
    expect(find.text('旧的书房电脑'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '收藏'));
    await tester.pumpAndSettle();
    expect(find.text('旧的书房电脑'), findsOneWidget);
  });
}
