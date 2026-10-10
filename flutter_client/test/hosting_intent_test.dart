import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/utils/hosting_intent.dart';
import 'package:rdesk/src/utils/platform_capabilities.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const store = HostingIntentStore();

  test('Windows 首次启动和升级后不会自动开启被控', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await store.shouldStartAtLaunch(TargetPlatform.windows), isFalse);
  });

  test('Windows 只恢复用户上次明确开启的被控', () async {
    SharedPreferences.setMockInitialValues({});

    await store.save(true);
    expect(await store.shouldStartAtLaunch(TargetPlatform.windows), isTrue);

    await store.save(false);
    expect(await store.shouldStartAtLaunch(TargetPlatform.windows), isFalse);
  });

  test('Mac 沿用启动即待命，由系统授权把关', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await store.shouldStartAtLaunch(TargetPlatform.macOS), isTrue);
  });

  test('Windows 可以作为被控端并支持无人值守', () {
    const windows = PlatformCapabilities.forPlatform(TargetPlatform.windows);

    expect(windows.canHost, isTrue);
    expect(windows.canUnattendedHost, isTrue);
    expect(windows.requiresHostOptIn, isTrue);
    expect(
        const PlatformCapabilities.forPlatform(TargetPlatform.macOS)
            .requiresHostOptIn,
        isFalse);
    expect(
        const PlatformCapabilities.forPlatform(TargetPlatform.linux).canHost,
        isFalse);
  });
}
