import 'package:flutter/services.dart';

class AndroidHostState {
  final String state;
  final bool hasPermission;

  /// 投屏授权被系统收回，必须由用户重新走一次系统弹窗。
  ///
  /// 与 `hasPermission == false` 的区别在于原因：这是「授权曾经有、被系统
  /// 收走了」，最常见的触发是被控端锁屏（STOP_REASON_KEYGUARD）。
  final bool needsReauthorization;
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
    this.needsReauthorization = false,
    required this.isRunning,
    required this.accessibilityEnabled,
    required this.overlayEnabled,
    required this.notificationsEnabled,
    required this.batteryOptimizationIgnored,
    required this.manufacturer,
    this.message,
  });

  /// 录屏授权一栏在界面上应显示的说明。
  ///
  /// 「被系统收回」必须与「从未授权」区分开：前者用户已经授权过，看到
  /// 「首次必须手动确认」只会困惑，而真正要做的是重新确认一次弹窗，并把
  /// 屏幕超时与锁屏关掉以免再次触发。
  String get captureDescription =>
      switch ((hasPermission, needsReauthorization)) {
        (true, _) => '已授予；守护模式可直接恢复前台服务。',
        (false, true) => '投屏已被系统收回（被控端锁屏会触发），需重新确认系统弹窗。'
            '建议把屏幕超时设为「永不」并关闭锁屏。',
        (false, false) => '首次必须手动确认系统录屏弹窗。',
      };

  factory AndroidHostState.fromMap(Map<dynamic, dynamic> map) {
    return AndroidHostState(
      state: (map['state'] as String?) ?? 'idle',
      hasPermission: (map['hasPermission'] as bool?) ?? false,
      needsReauthorization: (map['needsReauthorization'] as bool?) ?? false,
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
  static const _channel = MethodChannel('com.qsw.rdesk/android_host');

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

  Future<bool> setCaptureQuality({
    required double quality,
    int? fps,
  }) async {
    final result = await _channel.invokeMethod<bool>(
      'setCaptureQuality',
      <String, dynamic>{
        'quality': quality,
        if (fps != null) 'fps': fps,
      },
    );
    return result ?? false;
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

  Future<bool> performRemoteDragPath(List<List<double>> points) async {
    final result = await _channel.invokeMethod<bool>(
      'performRemoteDragPath',
      <String, dynamic>{
        'points': points,
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
  ///
  /// 只在 RDesk 处于前台时有效——窗口标志跟着 Activity 走。退到后台需要
  /// [setHostKeepScreenAwake]。
  Future<bool> setKeepScreenOn({required bool enabled}) async {
    final result = await _channel.invokeMethod<bool>(
      'setKeepScreenOn',
      <String, bool>{'enabled': enabled},
    );
    return result ?? false;
  }

  /// 托管期间由前台服务持有亮屏唤醒锁，App 退到后台仍然生效。
  ///
  /// 用途是躲开部分 ROM「锁屏即终止投屏」的策略（日志理由
  /// STOP_REASON_KEYGUARD）：屏幕不灭，锁屏就不出现。
  Future<bool> setHostKeepScreenAwake({required bool enabled}) async {
    final result = await _channel.invokeMethod<bool>(
      'setHostKeepScreenAwake',
      <String, bool>{'enabled': enabled},
    );
    return result ?? false;
  }
}
