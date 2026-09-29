import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rdesk/app.dart';
import 'package:rdesk/src/services/login_item_service.dart';
import 'package:rdesk/src/utils/router.dart';

void main() {
  group('Windows 开机启动', () {
    late List<String> scripts;
    late String stdout;
    late int exitCode;
    LoginItemService service() => LoginItemService(
        platform: TargetPlatform.windows,
        executable: r"C:\Users\o'neil\AppData\Local\Programs\RDesk\rdesk.exe",
        run: (exe, args) async {
          expect(exe, 'powershell.exe');
          scripts.add(args.last);
          return ProcessResult(0, exitCode, stdout, '');
        });
    setUp(() {
      scripts = [];
      stdout = 'false';
      exitCode = 0;
    });

    test('读取当前用户 Run 项并把「启动应用」中的关闭视为未开启', () async {
      stdout = 'true\r\n';
      final state = await service().status();
      expect(state.supported, isTrue);
      expect(state.enabled, isTrue);
      expect(scripts.single, contains(r'CurrentVersion\Run'));
      expect(scripts.single, contains(r'StartupApproved\Run'));
      expect(scripts.single, isNot(contains('HKLM')));
    });

    test('开启时写入带引号的程序路径并清除「启动应用」里的禁用标记', () async {
      stdout = 'true';
      final state = await service().set(true);
      expect(state.enabled, isTrue);
      expect(
          scripts.first,
          contains(
              r"""-Value '"C:\Users\o''neil\AppData\Local\Programs\RDesk\rdesk.exe" --hidden'"""));
      expect(
          scripts.first,
          contains(
              r"Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'"));
    });

    test('关闭时只删除 RDesk 自己的 Run 值', () async {
      await service().set(false);
      expect(scripts.first,
          r"Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'RDesk' -ErrorAction SilentlyContinue");
    });

    test('PowerShell 失败时给出可读错误', () async {
      exitCode = 1;
      await expectLater(service().status(), throwsA(isA<LoginItemException>()));
    });

    test('其他平台不支持', () async {
      final state =
          await const LoginItemService(platform: TargetPlatform.android)
              .status();
      expect(state.supported, isFalse);
    });
  });

  group('设置页启动开关', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    testWidgets('Windows 常规设置显示开机自动启动', (tester) async {
      appRouter.go('/settings');
      await tester.pumpWidget(const RDeskApp());
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('开机后自动启动 RDesk'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
    testWidgets('Mac 常规设置显示登录后自动打开', (tester) async {
      appRouter.go('/settings');
      await tester.pumpWidget(const RDeskApp());
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('登录 Mac 后自动打开 RDesk'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
    testWidgets('手机设置不显示开机启动', (tester) async {
      appRouter.go('/settings');
      await tester.pumpWidget(const RDeskApp());
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('开机后自动启动 RDesk'), findsNothing);
      expect(find.text('登录 Mac 后自动打开 RDesk'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });
}
