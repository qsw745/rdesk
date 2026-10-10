import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/remote_key_action.dart';

/// Input side of the Windows host. Everything is injected by the runner's
/// native `DesktopHostBridge`; no child process is involved.
///
/// Kept free of `Platform` checks so it can be exercised on any test host.
class WindowsHostDriver {
  const WindowsHostDriver(this._channel);

  final MethodChannel _channel;

  static const _scrollLines = 3;

  Future<bool> click(double x, double y) =>
      _mouse({'kind': 'click', 'x': x, 'y': y});

  Future<bool> rightClick(double x, double y) =>
      _mouse({'kind': 'rightClick', 'x': x, 'y': y});

  Future<bool> drag(double x, double y, double endX, double endY) =>
      _mouse({'kind': 'drag', 'x': x, 'y': y, 'endX': endX, 'endY': endY});

  Future<bool> typeText(String text) async {
    if (text.isEmpty) return false;
    return _invoke('typeText', {'text': text});
  }

  Future<bool> performAction(String action) async {
    final stroke = windowsRemoteKeyStrokeForAction(action);
    if (stroke != null) {
      return _invoke('performKeyPress', {
        'keyCode': stroke.virtualKey,
        'modifiers': stroke.modifiers.map((m) => m.name).toList(),
      });
    }
    switch (action) {
      case 'scroll_up':
        return _mouse({'kind': 'scroll', 'amount': _scrollLines});
      case 'scroll_down':
        return _mouse({'kind': 'scroll', 'amount': -_scrollLines});
      case 'wake_screen':
        return _invoke('wakeDisplay');
    }
    const monitorPrefix = 'switch_monitor_';
    if (action.startsWith(monitorPrefix)) {
      final index = int.tryParse(action.substring(monitorPrefix.length));
      if (index == null || index < 0) return false;
      return _invoke('switchDisplay', {'index': index}, true);
    }
    return false;
  }

  Future<bool> _mouse(Map<String, Object> arguments) async {
    final coordinates = ['x', 'y', 'endX', 'endY']
        .map((key) => arguments[key])
        .whereType<double>();
    if (coordinates.any((v) => v.isNaN || v < 0 || v > 1)) return false;
    return _invoke('performMouse', arguments);
  }

  /// Native input reports `false` when Windows discarded the events, which
  /// happens whenever an elevated window has focus. Never report that as done.
  Future<bool> _invoke(String method,
      [Map<String, Object>? arguments, bool nullMeansOk = false]) async {
    try {
      final ok = await _channel.invokeMethod<bool>(method, arguments);
      return ok ?? nullMeansOk;
    } on PlatformException catch (error) {
      debugPrint('[RDesk] windows host $method failed: ${error.code}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
