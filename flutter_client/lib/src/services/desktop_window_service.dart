import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Windows main-window behaviour implemented in the runner (`TrayBridge`):
/// closing the window can keep RDesk in the notification area so a PC woken
/// remotely stays online. Other platforms keep their native window handling.
class DesktopWindowService {
  static const _channel = MethodChannel('com.qsw.rdesk/window');
  final TargetPlatform? _platform;
  const DesktopWindowService({TargetPlatform? platform}) : _platform = platform;

  bool get supportsTray =>
      (_platform ?? defaultTargetPlatform) == TargetPlatform.windows;

  Future<void> setCloseToTray(bool enabled) async {
    if (!supportsTray) return;
    try {
      await _channel.invokeMethod<void>('setCloseToTray', enabled);
    } on MissingPluginException {
      // Older runner without the tray bridge: the window simply closes.
    } on PlatformException catch (e) {
      debugPrint('[RDesk] close to tray not applied: ${e.message}');
    }
  }
}
