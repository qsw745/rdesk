import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rdesk/app.dart';
import 'package:rdesk/src/providers/settings_provider.dart';
import 'package:rdesk/src/services/desktop_window_service.dart';
import 'package:rdesk/src/utils/router.dart';

class _RecordingWindow extends DesktopWindowService {
  final calls = <bool>[];
  _RecordingWindow() : super(platform: TargetPlatform.windows);
  @override
  Future<void> setCloseToTray(bool enabled) async => calls.add(enabled);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('默认关闭窗口时保留在托盘，并在启动时告知原生窗口', () async {
    SharedPreferences.setMockInitialValues({});
    final window = _RecordingWindow();
    final settings = SettingsProvider(window: window);
    await settings.loadSettings();
    expect(settings.closeToTray, isTrue);
    expect(window.calls, [true]);
  });

  test('关闭后持久保存，下次启动仍按用户选择通知原生窗口', () async {
    SharedPreferences.setMockInitialValues({});
    final window = _RecordingWindow();
    final settings = SettingsProvider(window: window);
    await settings.loadSettings();
    await settings.setCloseToTray(false);
    expect(window.calls.last, isFalse);

    final next = _RecordingWindow();
    await SettingsProvider(window: next).loadSettings();
    expect(next.calls, [false]);
  });

  test('非 Windows 平台不调用托盘通道', () async {
    const service = DesktopWindowService(platform: TargetPlatform.macOS);
    expect(service.supportsTray, isFalse);
    await service.setCloseToTray(true);
  });

  group('设置页', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    testWidgets('Windows 显示最小化到托盘开关', (tester) async {
      appRouter.go('/settings');
      await tester.pumpWidget(const RDeskApp());
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('关闭窗口时最小化到托盘'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
    testWidgets('Mac 不显示托盘开关', (tester) async {
      appRouter.go('/settings');
      await tester.pumpWidget(const RDeskApp());
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('关闭窗口时最小化到托盘'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });
}
