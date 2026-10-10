import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'platform_capabilities.dart';

/// The desktop user's own choice to let this computer be controlled.
///
/// macOS guards capture and input behind system permission prompts. Windows
/// has no such prompt, so there hosting may only start from a choice the user
/// made on this computer, and never from an install or an update.
class HostingIntentStore {
  const HostingIntentStore();

  static const _key = 'desktop_host.hosting_enabled';

  Future<bool> shouldStartAtLaunch(TargetPlatform platform) async {
    if (!PlatformCapabilities.forPlatform(platform).requiresHostOptIn) {
      return true;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  Future<void> save(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}
