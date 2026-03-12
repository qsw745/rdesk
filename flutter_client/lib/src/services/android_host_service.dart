import 'package:flutter/services.dart';

class AndroidHostState {
  final String state;
  final bool hasPermission;
  final bool isRunning;
  final bool accessibilityEnabled;
  final bool overlayEnabled;
  final bool notificationsEnabled;
  final bool batteryOptimizationIgnored;
  final String manufacturer;
  final String? message;

  const AndroidHostState({
    required this.state,
    required this.hasPermission,
    required this.isRunning,
    required this.accessibilityEnabled,
    required this.overlayEnabled,
    required this.notificationsEnabled,
    required this.batteryOptimizationIgnored,
    required this.manufacturer,
    this.message,
  });

  factory AndroidHostState.fromMap(Map<dynamic, dynamic> map) {
    return AndroidHostState(
      state: (map['state'] as String?) ?? 'idle',
      hasPermission: (map['hasPermission'] as bool?) ?? false,
      isRunning: (map['isRunning'] as bool?) ?? false,
      accessibilityEnabled: (map['accessibilityEnabled'] as bool?) ?? false,
      overlayEnabled: (map['overlayEnabled'] as bool?) ?? false,
      notificationsEnabled: (map['notificationsEnabled'] as bool?) ?? false,
      batteryOptimizationIgnored:
          (map['batteryOptimizationIgnored'] as bool?) ?? false,
      manufacturer: (map['manufacturer'] as String?) ?? '',
      message: map['message'] as String?,
    );
  }
}

class AndroidHostFrame {
  final Uint8List bytes;
  final int width;
  final int height;
  final int timestampMs;

  const AndroidHostFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.timestampMs,
  });

  factory AndroidHostFrame.fromMap(Map<dynamic, dynamic> map) {
    return AndroidHostFrame(
      bytes: (map['bytes'] as Uint8List?) ?? Uint8List(0),
      width: (map['width'] as int?) ?? 0,
      height: (map['height'] as int?) ?? 0,
      timestampMs: (map['timestampMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class AndroidHostService {
  AndroidHostService._();

  static final AndroidHostService instance = AndroidHostService._();
  static const _channel = MethodChannel('com.example.rdesk/android_host');

  Future<AndroidHostState> getState() async {
    final result = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('getScreenCaptureState');
    return AndroidHostState.fromMap(result ?? const <String, dynamic>{});
  }

  Future<AndroidHostState> requestPermission() async {
    final result = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('requestScreenCapturePermission');
    return AndroidHostState.fromMap(result ?? const <String, dynamic>{});
  }

  Future<AndroidHostState> startHosting() async {
    final result = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('startScreenCaptureService');
    return AndroidHostState.fromMap(result ?? const <String, dynamic>{});
  }

  Future<AndroidHostState> stopHosting() async {
    final result = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('stopScreenCaptureService');
    return AndroidHostState.fromMap(result ?? const <String, dynamic>{});
  }

  Future<AndroidHostFrame?> getLatestFrame() async {
    final result = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('getLatestCapturedFrame');
    if (result == null) {
      return null;
    }
    final bytes = result['bytes'];
    if (bytes is! Uint8List || bytes.isEmpty) {
      return null;
    }
    return AndroidHostFrame.fromMap(result);
  }

  Future<bool> showRemoteTapIndicator({
    required double normalizedX,
    required double normalizedY,
  }) async {
    final result = await _channel.invokeMethod<bool>(
      'showRemoteTapIndicator',
      <String, double>{
        'x': normalizedX,
        'y': normalizedY,
      },
    );
    return result ?? false;
  }

  Future<bool> performRemoteLongPress({
    required double normalizedX,
    required double normalizedY,
  }) async {
    final result = await _channel.invokeMethod<bool>(
      'performRemoteLongPress',
      <String, double>{
        'x': normalizedX,
        'y': normalizedY,
      },
    );
    return result ?? false;
  }

  Future<bool> performRemoteDrag({
    required double startX,
    required double startY,
    required double endX,
    required double endY,
  }) async {
    final result = await _channel.invokeMethod<bool>(
      'performRemoteDrag',
      <String, double>{
        'startX': startX,
        'startY': startY,
        'endX': endX,
        'endY': endY,
      },
    );
    return result ?? false;
  }

  Future<bool> performRemoteTextInput(String text) async {
    final result = await _channel.invokeMethod<bool>(
      'performRemoteTextInput',
      <String, String>{'text': text},
    );
    return result ?? false;
  }

  Future<bool> setClipboardText(String text) async {
    final result = await _channel.invokeMethod<bool>(
      'setClipboardText',
      <String, String>{'text': text},
    );
    return result ?? false;
  }

  Future<String?> getClipboardText() async {
    return _channel.invokeMethod<String>('getClipboardText');
  }

  Future<void> openAccessibilitySettings() async {
    await _channel.invokeMethod<void>('openAccessibilitySettings');
  }

  Future<void> openOverlaySettings() async {
    await _channel.invokeMethod<void>('openOverlaySettings');
  }

  Future<void> openNotificationSettings() async {
    await _channel.invokeMethod<void>('openNotificationSettings');
  }

  Future<void> openBatteryOptimizationSettings() async {
    await _channel.invokeMethod<void>('openBatteryOptimizationSettings');
  }

  Future<void> openAppDetailsSettings() async {
    await _channel.invokeMethod<void>('openAppDetailsSettings');
  }

  Future<bool> performRemoteAction(String action) async {
    final result = await _channel.invokeMethod<bool>(
      'performRemoteAction',
      <String, String>{'action': action},
    );
    return result ?? false;
  }

  /// Wake the screen and dismiss keyguard (if no secure lock is set).
  Future<bool> wakeScreen() async {
    final result = await _channel.invokeMethod<bool>('wakeScreen');
    return result ?? false;
  }

  /// Set FLAG_KEEP_SCREEN_ON to prevent screen from turning off.
  Future<bool> setKeepScreenOn({required bool enabled}) async {
    final result = await _channel.invokeMethod<bool>(
      'setKeepScreenOn',
      <String, bool>{'enabled': enabled},
    );
    return result ?? false;
  }
}
