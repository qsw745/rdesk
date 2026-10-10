import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rdesk/app.dart';
import 'package:rdesk/src/models/key_mapping.dart';
import 'package:rdesk/src/providers/settings_provider.dart';
import 'package:rdesk/src/utils/router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('按键映射保存后，重新加载仍然生效', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    expect(settings.windowsKeyMapping, WindowsKeyMapping.defaults);

    await settings.setWindowsKeyMapping(
        const WindowsKeyMapping(command: RemoteModifier.ctrl));

    final reloaded = SettingsProvider();
    await reloaded.loadWindowsKeyMapping();
    expect(reloaded.windowsKeyMapping.command, RemoteModifier.ctrl);
    expect(reloaded.windowsKeyMapping.option, RemoteModifier.alt);
  });

  test('存储内容损坏时使用默认映射', () async {
    SharedPreferences.setMockInitialValues(
        {'rdesk.windows_key_mapping': '{not json'});
    final settings = SettingsProvider();

    await settings.loadWindowsKeyMapping();

    expect(settings.windowsKeyMapping, WindowsKeyMapping.defaults);
  });

  group('设置页', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('Mac 上提供远控 Windows 的按键映射，改动立即保存，可还原默认', (tester) async {
      tester.view.physicalSize = const Size(1400, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      appRouter.go('/settings');
      await tester.pumpWidget(const RDeskApp());
      await tester.pumpAndSettle();

      expect(find.text('远控 Windows 按键映射'), findsOneWidget);
      for (final row in [
        'Command (⌘) 键',
        'Option (⌥) 键',
        'Control (⌃) 键',
        'Delete 键',
        'Fn + Delete 键'
      ]) {
        expect(find.text(row), findsOneWidget, reason: row);
      }

      await tester.tap(find.byKey(const ValueKey('key-mapping-command')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ctrl').last);
      await tester.pumpAndSettle();

      final context = tester.element(find.text('远控 Windows 按键映射'));
      final settings = context.read<SettingsProvider>();
      expect(settings.windowsKeyMapping.command, RemoteModifier.ctrl);
      final prefs = await SharedPreferences.getInstance();
      expect(
          (jsonDecode(prefs.getString('rdesk.windows_key_mapping')!)
              as Map)['command'],
          'ctrl');

      await tester.tap(find.text('还原默认按键映射'));
      await tester.pumpAndSettle();
      expect(settings.windowsKeyMapping, WindowsKeyMapping.defaults);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('Windows 键盘不需要映射，设置页不显示该项', (tester) async {
      tester.view.physicalSize = const Size(1400, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      appRouter.go('/settings');
      await tester.pumpWidget(const RDeskApp());
      await tester.pumpAndSettle();

      expect(find.text('远控 Windows 按键映射'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });
}
