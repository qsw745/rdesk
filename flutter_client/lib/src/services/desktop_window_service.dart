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

  /// Windows shows no system indicator while the screen is being viewed, so
  /// the tray says so and offers to disconnect.
  Future<void> setViewerActive(bool active) async {
    if (!supportsTray) return;
    try {
      await _channel.invokeMethod<void>('setViewerActive', active);
    } on MissingPluginException {
      // Older runner without the indicator.
    } on PlatformException catch (e) {
      debugPrint('[RDesk] viewer indicator not applied: ${e.message}');
    }
  }

  /// A system notification from the tray icon, for things that happen while
  /// the window may be hidden.
  Future<void> showNotice(String title, String body) async {
    if (!supportsTray) return;
    try {
      await _channel.invokeMethod<void>(
          'showNotice', <String, String>{'title': title, 'body': body});
    } on MissingPluginException {
      // Older runner without notices.
    } on PlatformException catch (e) {
      debugPrint('[RDesk] notice not shown: ${e.message}');
    }
  }

  /// The tray menu's requests while this computer is being viewed:
  /// throw the viewer out, or stop being controllable altogether.
  void onHostRequests({
    Future<void> Function()? disconnect,
    Future<void> Function()? stopHosting,
  }) {
    if (!supportsTray) return;
    if (disconnect == null && stopHosting == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'disconnectViewers') await disconnect?.call();
      if (call.method == 'stopHosting') await stopHosting?.call();
    });
  }
}
