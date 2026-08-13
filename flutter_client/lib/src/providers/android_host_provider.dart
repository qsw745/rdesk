import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/device.dart';
import '../services/rdesk_bridge_service.dart';
import '../services/android_host_service.dart';
import '../utils/router.dart';
import '../widgets/incoming_connection_dialog.dart';

class AndroidHostProvider extends ChangeNotifier {
  final _bridge = RdeskBridgeService.instance;
  final _service = AndroidHostService.instance;

  static const _guardModeEnabledKey = 'android_guard_mode_enabled';
  static const _keepScreenAwakeKey = 'android_keep_screen_awake';
  static const _previewPollInterval = Duration(milliseconds: 80);
  static const _relayCommandPollInterval = Duration(milliseconds: 60);

  /// 静止画面下的保活重传间隔。
  ///
  /// 原生侧用 ImageReader 挂在 VirtualDisplay 上，**只有屏幕内容变化时才产生新帧**，
  /// 因此手机静置时 [AndroidHostFrame.timestampMs] 会停止推进。若此时因为
  /// 「时间戳没变」而跳过上传，中继服务器上的画面会在 PREVIEW_TTL_MS（30 秒）后过期，
  /// 观看端拉流得到 503——而注册心跳仍在跑，设备看起来一直「在线」。
  ///
  /// 所以即使帧没变化，也要按此间隔把最后一帧重发一次。
  ///
  /// 取值需同时小于两个阈值，且留足余量：
  ///   - 服务端帧 TTL：30 秒（PREVIEW_TTL_MS）
  ///   - 观看端判定离线的无帧时长：30 秒（SessionProvider._offlineGracePeriod）
  /// 此前取 10 秒，与当时同为 10 秒的离线判定撞在一起，余量为零——
  /// 网络稍有抖动，观看端就可能先一步判掉线。
  static const _relayKeepAliveInterval = Duration(seconds: 5);

  /// 保活重传的封顶时长。
  ///
  /// 保活只在「采集活着、但画面恰好静止」时才是正确行为。若原生侧的投屏已经
  /// 被系统拆掉，最后一帧会永远停在那里——此时继续重传等于把一张定格的死图
  /// 伪装成实时画面，观看端看到的屏幕再也不会更新，比设备直接离线更难排查。
  ///
  /// 因此超过此时长仍未见到新帧，就停止重传并回读一次原生状态，
  /// 让设备如实反映为不可用。
  static const _relayKeepAliveMaxSpan = Duration(seconds: 90);

  /// 托管期间回读原生采集状态的间隔。
  ///
  /// 此前 [_state] 只在用户操作时刷新，原生把状态置为 ERROR 也无人知晓。
  static const _captureStateRefreshInterval = Duration(seconds: 15);

  // ── 上行自适应档位。取值与原生 ScreenCaptureStore.setCaptureQuality 的三档对应 ──
  static const _qualityHigh = 0.9; // 1920 长边 / q85 / 15fps
  static const _qualityMedium = 0.75; // 1440 长边 / q75 / 12fps
  static const _qualityLow = 0.5; // 960 长边 / q55 / 10fps

  /// 单帧上传平均耗时超过此值即判定上行喂不动，降档。
  /// 中档目标 12fps（83ms 一帧），留出约 4 倍余量再动手，避免抖动导致来回跳。
  static const _uploadSlowThresholdMs = 350;

  /// 平均耗时低于此值且用户要求更高画质时，升档。
  static const _uploadFastThresholdMs = 120;

  /// 两次调档之间的最小间隔，防止在阈值边缘反复横跳。
  static const _qualityShiftCooldown = Duration(seconds: 8);

  AndroidHostState _state = const AndroidHostState(
    state: 'idle',
    hasPermission: false,
    isRunning: false,
    accessibilityEnabled: false,
    overlayEnabled: false,
    notificationsEnabled: false,
    batteryOptimizationIgnored: false,
    manufacturer: '',
  );
  AndroidHostFrame? _previewFrame;
  bool _busy = false;
  String? _error;
  Timer? _previewTimer;
  Timer? _registrationTimer;
  Timer? _relayCommandTimer;
  HttpServer? _lanRelayServer;
  String? _lanRelayEndpoint;
  DeviceInfo? _localDevice;
  String? _relayHostToken;
  bool _guardModeEnabled = false;
  bool _keepScreenAwakeEnabled = false;
  bool _relayCommandBusy = false;
  bool _relayUploadBusy = false;
  int? _lastUploadedFrameTimestampMs;
  int? _lastRelayUploadAtMs;
  int _relayUploadFailureStreak = 0;
  int _relayUploadRetryAfterMs = 0;
  int? _lastFrameAdvancedAtMs;

  int _relayCommandFailureStreak = 0;
  int _relayCommandRetryAfterMs = 0;

  /// 帧上传耗时的滑动平均，上行拥塞的唯一可观测信号。
  double? _uploadMsAverage;

  /// 观看端明确要求的画质档位，自适应升档不会越过它。
  double _requestedQuality = _qualityMedium;

  /// 当前实际生效的画质档位。
  double _effectiveQuality = _qualityMedium;
  int? _lastQualityShiftAtMs;
  Timer? _captureStateTimer;
  // LAN session tokens issued via /session/trust (password-authenticated).
  final Set<String> _lanSessionTokens = {};
  String? _lastRemoteTap;
  String? _lastRemoteAction;
  String? _lastRemoteGesture;
  String? _lastRemoteText;
  String? _lastRemoteClipboard;

  AndroidHostState get state => _state;
  AndroidHostFrame? get previewFrame => _previewFrame;
  String? get lanRelayEndpoint => _lanRelayEndpoint;
  String? get lastRemoteTap => _lastRemoteTap;
  String? get lastRemoteAction => _lastRemoteAction;
  String? get lastRemoteGesture => _lastRemoteGesture;
  String? get lastRemoteText => _lastRemoteText;
  String? get lastRemoteClipboard => _lastRemoteClipboard;
  bool get busy => _busy;
  String? get error => _error;
  bool get canDisconnectViewers => _state.isRunning && _localDevice != null;
  bool get guardModeEnabled => _guardModeEnabled;
  bool get keepScreenAwakeEnabled => _keepScreenAwakeEnabled;
  bool get isReadyForRemoteRequests =>
      _state.hasPermission &&
      _state.accessibilityEnabled &&
      _state.notificationsEnabled &&
      _state.batteryOptimizationIgnored;
  bool get needsManualScreenCaptureConsent => !_state.hasPermission;
  String get autostartGuidance => switch (_state.manufacturer.toLowerCase()) {
        'xiaomi' ||
        'redmi' ||
        'poco' =>
          '建议在 MIUI/HyperOS 的“自启动”和“无限制电量”中允许 RDesk 常驻。',
        'oppo' || 'oneplus' || 'realme' => '建议在系统管家里允许 RDesk 自启动，并关闭后台冻结/耗电限制。',
        'vivo' || 'iqoo' => '建议在 i 管家中允许 RDesk 后台高耗电、自启动和悬浮窗。',
        'huawei' || 'honor' => '建议在启动管理中允许 RDesk 自启动，并关闭电池优化。',
        'samsung' => '建议把 RDesk 加入“永不休眠的应用”，避免系统回收。',
        _ => '如果系统有“自启动/后台保护/无限制电量”设置，建议把 RDesk 加入白名单。',
      };

  /// 托管启动后必须成套执行的动作。
  ///
  /// 此前 initialize / requestPermission / startHosting 各自抄了一份，
  /// 而 refresh 只抄了其中两步——漏掉 [_registerPreviewHost] 导致
  /// 「采集在跑、设备却没在服务端登记」：App 内一切正常，对外完全不可见，
  /// 且 _relayHostToken 为 null 时 [_uploadRelayFrame] 会静默返回，连帧也不传。
  /// 收敛为一处，避免再次漏步。
  Future<void> _beginHostingSession() async {
    if (!_state.isRunning) {
      return;
    }
    await _service.setKeepScreenOn(enabled: true);
    _ensurePreviewPolling();
    await _ensureLanRelay();
    await _registerPreviewHost();
    _ensureRelayCommandPolling();
  }

  Future<void> initialize({bool enabled = true}) async {
    if (!enabled) {
      return;
    }
    await _run(() async {
      _localDevice = await _bridge.getLocalDeviceInfo();
      final prefs = await SharedPreferences.getInstance();
      _guardModeEnabled = prefs.getBool(_guardModeEnabledKey) ?? false;
      _keepScreenAwakeEnabled = prefs.getBool(_keepScreenAwakeKey) ?? false;
      // 必须回灌给原生：进程重启后 ScreenCaptureStore 的标记是默认值，
      // 只读本地偏好会让开关显示为开、实际没生效。
      await _service.setHostKeepScreenAwake(enabled: _keepScreenAwakeEnabled);
      _state = await _service.getState();
      if (_guardModeEnabled && _state.hasPermission && !_state.isRunning) {
        _state = await _service.startHosting();
      }
      await _beginHostingSession();
    }, clearError: false);
  }

  Future<void> requestPermission() async {
    await _run(() async {
      _state = await _service.requestPermission();
      if (_guardModeEnabled && _state.hasPermission && !_state.isRunning) {
        _state = await _service.startHosting();
        await _beginHostingSession();
      }
    });
  }

  Future<void> startHosting() async {
    await _run(() async {
      _state = await _service.startHosting();
      await _beginHostingSession();
    });
  }

  Future<void> stopHosting() async {
    await _run(() async {
      _state = await _service.stopHosting();
      if (!_state.isRunning) {
        _previewTimer?.cancel();
        _previewTimer = null;
        _registrationTimer?.cancel();
        _registrationTimer = null;
        _relayCommandTimer?.cancel();
        _relayCommandTimer = null;
        _captureStateTimer?.cancel();
        _captureStateTimer = null;
        final oldToken = _relayHostToken;
        _relayHostToken = null;
        _resetRelayUploadState();
        if (_localDevice != null && oldToken != null) {
          try {
            await _bridge.unregisterPreviewHost(_localDevice!.deviceId,
                hostToken: oldToken);
          } catch (_) {
            // Ignore best-effort unregister failures.
          }
        }
        await _closeLanRelay();
      }
    });
  }

  Future<void> refresh() async {
    await _run(() async {
      _state = await _service.getState();
      // 走完整启动序列：此前这里只重启了轮询，没有重新注册，
      // 刷新状态或开启守护模式后设备会从服务端消失。
      await _beginHostingSession();
    }, clearError: false);
  }

  Future<void> openAccessibilitySettings() =>
      _service.openAccessibilitySettings();

  /// 托管期间保持屏幕常亮。
  ///
  /// 部分 ROM 在锁屏出现时直接终止投屏（日志理由 STOP_REASON_KEYGUARD），而
  /// Android 不允许静默重新授权，被终止后必须用户再确认一次系统弹窗——无人值守
  /// 的被控端就此失联。屏幕不灭则锁屏不出现。默认关闭：代价是耗电与烧屏风险。
  Future<void> setKeepScreenAwakeEnabled(bool enabled) async {
    _keepScreenAwakeEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keepScreenAwakeKey, enabled);
    await _service.setHostKeepScreenAwake(enabled: enabled);
    notifyListeners();
  }

  Future<void> setGuardModeEnabled(bool enabled) async {
    _guardModeEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_guardModeEnabledKey, enabled);
    notifyListeners();
    if (enabled) {
      await refresh();
      if (_state.hasPermission && !_state.isRunning) {
        await startHosting();
      }
    } else if (_state.isRunning) {
      await stopHosting();
    }
  }

  Future<void> openOverlaySettings() => _service.openOverlaySettings();

  Future<void> openNotificationSettings() =>
      _service.openNotificationSettings();

  Future<void> openBatteryOptimizationSettings() =>
      _service.openBatteryOptimizationSettings();

  Future<void> openAppDetailsSettings() => _service.openAppDetailsSettings();

  Future<bool> disconnectCurrentViewer() async {
    final device = _localDevice;
    final hostToken = _relayHostToken;
    if (!_state.isRunning || device == null) {
      return false;
    }

    await _run(() async {
      // 1) Unregister from relay to remove preview entry AND all viewer
      //    sessions atomically.  This is the primary mechanism that forces
      //    relay-connected viewers to get 401 on next frame fetch.
      if (hostToken != null && hostToken.isNotEmpty) {
        try {
          await _bridge.unregisterPreviewHost(
            device.deviceId,
            hostToken: hostToken,
          );
        } catch (_) {
          // Fallback: try disconnecting viewers individually.
          try {
            await _bridge.disconnectHostedViewers(
              deviceId: device.deviceId,
              hostToken: hostToken,
            );
          } catch (_) {}
        }
      }

      // 2) Close LAN relay to cut direct connections immediately
      await _closeLanRelay();

      // 3) Clear host token so fresh registration gets a new one
      _relayHostToken = null;
      _resetRelayUploadState();

      // 4) Revoke auto-trust and rotate the temporary password so the kicked
      // viewer cannot immediately auto-reconnect with cached trust/password.
      final settings = await _bridge.loadSettings();
      await _bridge.clearTrustedIncomingViewers();
      final permanentPassword = settings.permanentPassword?.trim();
      if (permanentPassword == null || permanentPassword.isEmpty) {
        await _bridge.generateTemporaryPassword();
      }

      // 5) Re-open LAN relay on a new port and re-register with fresh token
      await _ensureLanRelay();
      await _registerPreviewHost();
      _ensureRelayCommandPolling();
    });
    return _error == null;
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _registrationTimer?.cancel();
    _relayCommandTimer?.cancel();
    _captureStateTimer?.cancel();
    unawaited(_closeLanRelay(notify: false));
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool clearError = true,
  }) async {
    _busy = true;
    if (clearError) {
      _error = null;
    }
    notifyListeners();

    try {
      await action();
    } catch (error) {
      _error = error.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _ensurePreviewPolling() {
    _previewTimer?.cancel();
    if (!_state.isRunning) {
      _captureStateTimer?.cancel();
      _captureStateTimer = null;
      return;
    }
    unawaited(_pollPreviewFrame());
    _previewTimer = Timer.periodic(
      _previewPollInterval,
      (_) => unawaited(_pollPreviewFrame()),
    );
    _ensureCaptureStatePolling();
  }

  Future<void> _pollPreviewFrame() async {
    try {
      final frame = await _service.getLatestFrame();
      if (frame != null) {
        final changed = _previewFrame?.timestampMs != frame.timestampMs ||
            _previewFrame?.bytes.length != frame.bytes.length;
        _previewFrame = frame;
        if (changed) {
          notifyListeners();
        }
        await _uploadRelayFrame(frame);
      }
    } catch (_) {
      // Ignore transient preview polling failures while the service is warming up.
    }
  }

  /// 托管期间周期回读原生采集状态。
  ///
  /// 投屏被系统回收时原生会把状态置为 ERROR，但此前 Dart 侧只在用户操作时刷新
  /// [_state]，导致「采集已死、上层仍在推流」的状态可以无限持续下去。
  void _ensureCaptureStatePolling() {
    _captureStateTimer?.cancel();
    if (!_state.isRunning) {
      return;
    }
    _captureStateTimer = Timer.periodic(
      _captureStateRefreshInterval,
      (_) => unawaited(_refreshCaptureState()),
    );
  }

  Future<void> _refreshCaptureState() async {
    try {
      final next = await _service.getState();
      final wasRunning = _state.isRunning;
      _state = next;
      if (wasRunning && !next.isRunning) {
        debugPrint('[rdesk-host] 原生采集已停止（投屏被回收），终止推流与广播');
        _previewTimer?.cancel();
        _previewTimer = null;
        _previewFrame = null;
        _resetRelayUploadState();
        _error = '屏幕采集已被系统中断，请重新开启共享';
        await _closeLanRelay(notify: false);
        _captureStateTimer?.cancel();
        _captureStateTimer = null;
      }
      notifyListeners();
    } catch (error) {
      debugPrint('[rdesk-host] 回读采集状态失败: $error');
    }
  }

  void _ensureRelayCommandPolling() {
    _relayCommandTimer?.cancel();
    if (!_state.isRunning || _relayHostToken == null || _localDevice == null) {
      return;
    }
    unawaited(_pollRelayCommand());
    _relayCommandTimer = Timer.periodic(
      _relayCommandPollInterval,
      (_) => unawaited(_pollRelayCommand()),
    );
  }

  Future<void> _ensureLanRelay() async {
    if (_lanRelayServer != null) {
      return;
    }

    const lanPort = 21116;
    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.anyIPv4, lanPort);
    } catch (_) {
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    _lanRelayServer = server;
    final localIp = await _resolveLocalIpv4();
    if (localIp != null) {
      _lanRelayEndpoint = '$localIp:${server.port}';
    } else {
      _lanRelayEndpoint = '127.0.0.1:${server.port}';
    }
    notifyListeners();
    await _registerPreviewHost();

    unawaited(
      server.forEach((request) async {
        final response = request.response;
        response.headers.set('Cache-Control', 'no-store');

        // --- Unauthenticated endpoints ---

        if (request.uri.path == '/health') {
          response.headers.contentType = ContentType.json;
          response.write(
            jsonEncode(<String, Object?>{
              'state': _state.state,
              'running': _state.isRunning,
              'hasPermission': _state.hasPermission,
              'accessibilityEnabled': _state.accessibilityEnabled,
              'overlayEnabled': _state.overlayEnabled,
              'notificationsEnabled': _state.notificationsEnabled,
              'batteryOptimizationIgnored': _state.batteryOptimizationIgnored,
              'hasFrame': _previewFrame != null,
              'endpoint': _lanRelayEndpoint,
              'platform': Platform.operatingSystem,
            }),
          );
          await response.close();
          return;
        }

        // /session/trust: validate password and issue a session token.
        if (request.uri.path == '/session/trust' && request.method == 'POST') {
          final body = await utf8.decoder.bind(request).join();
          final payload = jsonDecode(body) as Map<String, dynamic>;
          final deviceId = payload['deviceId'] as String?;
          final hostname = payload['hostname'] as String?;
          final peerOs = payload['peerOs'] as String?;
          final password = payload['password'] as String?;
          if (deviceId == null || hostname == null || peerOs == null) {
            response.statusCode = HttpStatus.badRequest;
            response.write('missing viewer info');
            await response.close();
            return;
          }
          // Validate password if the host has one set.
          final hostPassword = await _bridge.getActiveAccessPassword();
          if (hostPassword.isNotEmpty) {
            if (password == null || password != hostPassword) {
              response.statusCode = HttpStatus.unauthorized;
              response.headers.contentType = ContentType.json;
              response.write(jsonEncode(
                  <String, Object?>{'ok': false, 'error': 'invalid password'}));
              await response.close();
              return;
            }
          }

          // Auto-wake screen when a remote viewer connects
          try {
            await _service.wakeScreen();
          } catch (_) {}

          await _bridge.trustIncomingViewer(
            deviceId: deviceId,
            hostname: hostname,
            peerOs: peerOs,
          );
          await _registerPreviewHost();
          // Issue a session token for subsequent requests.
          final rng = Random.secure();
          final sessionToken = List.generate(32, (_) => rng.nextInt(256))
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
          _lanSessionTokens.add(sessionToken);
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(<String, Object?>{
            'ok': true,
            'session_token': sessionToken,
          }));
          await response.close();
          return;
        }

        // --- All other endpoints require a valid session token ---
        final token = request.uri.queryParameters['session_token'] ??
            request.headers.value('x-session-token') ??
            '';
        if (!_lanSessionTokens.contains(token)) {
          response.statusCode = HttpStatus.unauthorized;
          response.write('unauthorized');
          await response.close();
          return;
        }

        if (request.uri.path == '/frame.jpg') {
          final frame = _previewFrame;
          if (frame == null || frame.bytes.isEmpty) {
            response.statusCode = HttpStatus.serviceUnavailable;
            response.write('frame unavailable');
            await response.close();
            return;
          }

          response.headers.contentType = ContentType('image', 'jpeg');
          response.headers.set('X-RDesk-Width', frame.width.toString());
          response.headers.set('X-RDesk-Height', frame.height.toString());
          response.headers
              .set('X-RDesk-Timestamp', frame.timestampMs.toString());
          response.headers
              .set('X-RDesk-Captured-At', frame.timestampMs.toString());
          response.add(frame.bytes);
          await response.close();
          return;
        }

        if (request.uri.path == '/input/tap' && request.method == 'POST') {
          final body = await utf8.decoder.bind(request).join();
          final payload = jsonDecode(body) as Map<String, dynamic>;
          final x = (payload['x'] as num?)?.toDouble();
          final y = (payload['y'] as num?)?.toDouble();
          if (x == null || y == null) {
            response.statusCode = HttpStatus.badRequest;
            response.write('missing coordinates');
            await response.close();
            return;
          }

          _lastRemoteTap = '${(x * 100).round()}%, ${(y * 100).round()}%';
          notifyListeners();
          final ok = await _service.showRemoteTapIndicator(
            normalizedX: x,
            normalizedY: y,
          );

          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(<String, Object?>{'ok': ok}));
          await response.close();
          return;
        }

        if (request.uri.path == '/input/action' && request.method == 'POST') {
          final body = await utf8.decoder.bind(request).join();
          final payload = jsonDecode(body) as Map<String, dynamic>;
          final action = payload['action'] as String?;
          if (action == null || action.isEmpty) {
            response.statusCode = HttpStatus.badRequest;
            response.write('missing action');
            await response.close();
            return;
          }

          _lastRemoteAction = action;
          notifyListeners();

          bool ok;
          if (action == 'wake_screen') {
            ok = await _service.wakeScreen();
          } else {
            ok = await _service.performRemoteAction(action);
          }
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(<String, Object?>{'ok': ok}));
          await response.close();
          return;
        }

        if (request.uri.path == '/input/long_press' &&
            request.method == 'POST') {
          final body = await utf8.decoder.bind(request).join();
          final payload = jsonDecode(body) as Map<String, dynamic>;
          final x = (payload['x'] as num?)?.toDouble();
          final y = (payload['y'] as num?)?.toDouble();
          if (x == null || y == null) {
            response.statusCode = HttpStatus.badRequest;
            response.write('missing coordinates');
            await response.close();
            return;
          }

          _lastRemoteGesture =
              'long_press ${(x * 100).round()}%, ${(y * 100).round()}%';
          notifyListeners();
          final ok = await _service.performRemoteLongPress(
            normalizedX: x,
            normalizedY: y,
          );
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(<String, Object?>{'ok': ok}));
          await response.close();
          return;
        }

        if (request.uri.path == '/input/drag' && request.method == 'POST') {
          final body = await utf8.decoder.bind(request).join();
          final payload = jsonDecode(body) as Map<String, dynamic>;
          final startX = (payload['startX'] as num?)?.toDouble();
          final startY = (payload['startY'] as num?)?.toDouble();
          final endX = (payload['endX'] as num?)?.toDouble();
          final endY = (payload['endY'] as num?)?.toDouble();
          if (startX == null ||
              startY == null ||
              endX == null ||
              endY == null) {
            response.statusCode = HttpStatus.badRequest;
            response.write('missing drag coordinates');
            await response.close();
            return;
          }

          _lastRemoteGesture =
              'drag ${(startX * 100).round()}%, ${(startY * 100).round()}% -> ${(endX * 100).round()}%, ${(endY * 100).round()}%';
          notifyListeners();
          final ok = await _service.performRemoteDrag(
            startX: startX,
            startY: startY,
            endX: endX,
            endY: endY,
          );
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(<String, Object?>{'ok': ok}));
          await response.close();
          return;
        }

        if (request.uri.path == '/input/drag_path' &&
            request.method == 'POST') {
          final body = await utf8.decoder.bind(request).join();
          final payload = jsonDecode(body) as Map<String, dynamic>;
          final rawPoints = payload['points'] as List<dynamic>?;
          if (rawPoints == null || rawPoints.length < 2) {
            response.statusCode = HttpStatus.badRequest;
            response.write('missing points');
            await response.close();
            return;
          }
          final points = rawPoints
              .map((p) => [(p as List<dynamic>)[0] as double, p[1] as double])
              .toList();
          _lastRemoteGesture = 'drag_path ${points.length} points';
          notifyListeners();
          final ok = await _service.performRemoteDragPath(points);
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(<String, Object?>{'ok': ok}));
          await response.close();
          return;
        }

        if (request.uri.path == '/input/text' && request.method == 'POST') {
          final body = await utf8.decoder.bind(request).join();
          final payload = jsonDecode(body) as Map<String, dynamic>;
          final text = payload['text'] as String?;
          if (text == null) {
            response.statusCode = HttpStatus.badRequest;
            response.write('missing text');
            await response.close();
            return;
          }

          _lastRemoteText = text;
          notifyListeners();
          final ok = await _service.performRemoteTextInput(text);
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(<String, Object?>{'ok': ok}));
          await response.close();
          return;
        }

        if (request.uri.path == '/clipboard/set' && request.method == 'POST') {
          final body = await utf8.decoder.bind(request).join();
          final payload = jsonDecode(body) as Map<String, dynamic>;
          final text = payload['text'] as String?;
          if (text == null) {
            response.statusCode = HttpStatus.badRequest;
            response.write('missing clipboard text');
            await response.close();
            return;
          }

          _lastRemoteClipboard = text;
          notifyListeners();
          final ok = await _service.setClipboardText(text);
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(<String, Object?>{'ok': ok}));
          await response.close();
          return;
        }

        if (request.uri.path == '/clipboard/get' && request.method == 'GET') {
          final text = await _service.getClipboardText();
          _lastRemoteClipboard = text;
          notifyListeners();
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(<String, Object?>{'text': text}));
          await response.close();
          return;
        }

        if (request.uri.path == '/settings/quality' &&
            request.method == 'POST') {
          final body = await utf8.decoder.bind(request).join();
          final payload = jsonDecode(body) as Map<String, dynamic>;
          final ok = await _applyCaptureQualityPayload(payload);
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(<String, Object?>{'ok': ok}));
          await response.close();
          return;
        }

        response.statusCode = HttpStatus.notFound;
        response.write('not found');
        await response.close();
      }),
    );
  }

  Future<void> _closeLanRelay({bool notify = true}) async {
    final server = _lanRelayServer;
    _lanRelayServer = null;
    _lanRelayEndpoint = null;
    _resetRelayUploadState();
    // Revoke tokens first so in-flight requests get 401 (triggering viewer
    // termination) before the TCP listener is torn down.
    _lanSessionTokens.clear();
    if (server != null) {
      // Give in-flight requests a moment to receive 401 before closing.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await server.close(force: true);
    }
    if (notify) {
      notifyListeners();
    }
  }

  Future<String?> _resolveLocalIpv4() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final candidates = <({int score, String address})>[];

    for (final interface in interfaces) {
      final name = interface.name.toLowerCase();
      final score = switch (name) {
        final value
            when value.contains('wlan') ||
                value.contains('wifi') ||
                value.contains('eth') ||
                value.contains('en') ||
                value.contains('ap') =>
          0,
        final value
            when value.contains('rmnet') ||
                value.contains('ccmni') ||
                value.contains('pdp') ||
                value.contains('cell') ||
                value.contains('mobile') =>
          2,
        _ => 1,
      };

      for (final address in interface.addresses) {
        final raw = address.address;
        if (address.isLoopback || !raw.contains('.')) {
          continue;
        }
        candidates.add((score: score, address: raw));
      }
    }

    if (candidates.isEmpty) {
      return null;
    }

    candidates.sort((left, right) => left.score.compareTo(right.score));
    return candidates.first.address;
  }

  Future<void> _registerPreviewHost() async {
    final device = _localDevice;
    final endpoint = _lanRelayEndpoint;
    if (device == null || endpoint == null || !_state.isRunning) {
      return;
    }

    // Cannot unregister without a valid host_token; skip when null.

    final password = await _bridge.getActiveAccessPassword();
    final settings = await _bridge.loadSettings();
    final trustedViewerIds = await _bridge.listTrustedIncomingViewerIds();
    final authToken = await _bridge.getAccountToken();

    final hostToken = await _bridge.registerPreviewHost(
      deviceId: device.deviceId,
      endpoint: endpoint,
      platform: device.os,
      hostname: device.hostname,
      password: password,
      autoAccept: settings.autoAccept,
      trustedViewerIds: trustedViewerIds,
      authToken: authToken,
      hostToken: _relayHostToken,
    );
    if (hostToken != null && hostToken.isNotEmpty) {
      _relayHostToken = hostToken;
    }

    _registrationTimer?.cancel();
    _registrationTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_registerPreviewHost()),
    );
    _ensureRelayCommandPolling();
  }

  /// 重置中继上传的全部游标。
  ///
  /// 这三个字段必须一起清空：只清时间戳会让保活计时残留，
  /// 下次托管启动后首帧可能被延迟到一个保活周期之后才发出。
  void _resetRelayUploadState() {
    _lastUploadedFrameTimestampMs = null;
    _lastRelayUploadAtMs = null;
    _relayUploadFailureStreak = 0;
    _relayUploadRetryAfterMs = 0;
    _lastFrameAdvancedAtMs = null;
    _uploadMsAverage = null;
    _lastQualityShiftAtMs = null;
    _relayCommandFailureStreak = 0;
    _relayCommandRetryAfterMs = 0;
    // 上行长连与时钟校准都绑在这次托管上，一并释放。
    _bridge.closeHostClient();
  }

  Future<void> _uploadRelayFrame(AndroidHostFrame frame) async {
    final device = _localDevice;
    final hostToken = _relayHostToken;
    if (device == null ||
        hostToken == null ||
        hostToken.isEmpty ||
        _relayUploadBusy ||
        frame.bytes.isEmpty) {
      return;
    }

    // 画面未变化时仍需按 _relayKeepAliveInterval 重传，否则静置的设备会在
    // 服务端 30 秒 TTL 后变成「在线但无画面」，观看端只能拿到 503。
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // 上传失败后按退避等待再重试。预览轮询是 80ms 一次，若失败时立即重试，
    // 服务器不可达期间会打出每秒十几次请求的风暴。
    if (nowMs < _relayUploadRetryAfterMs) {
      return;
    }

    final frameUnchanged = _lastUploadedFrameTimestampMs == frame.timestampMs;
    if (!frameUnchanged) {
      _lastFrameAdvancedAtMs = nowMs;
    }

    if (frameUnchanged) {
      // 画面长时间没有推进：不再重传，并回读原生状态确认采集是否已经死亡。
      // 宁可让设备显示为离线，也不能把定格的旧图当作实时画面继续供应。
      final advancedAtMs = _lastFrameAdvancedAtMs ??= nowMs;
      if (nowMs - advancedAtMs >= _relayKeepAliveMaxSpan.inMilliseconds) {
        debugPrint(
          '[rdesk-host] 画面已 ${_relayKeepAliveMaxSpan.inSeconds} 秒未更新，'
          '停止保活重传并回读采集状态',
        );
        unawaited(_refreshCaptureState());
        return;
      }

      final lastUploadAtMs = _lastRelayUploadAtMs;
      final keepAliveDue = lastUploadAtMs == null ||
          nowMs - lastUploadAtMs >= _relayKeepAliveInterval.inMilliseconds;
      if (!keepAliveDue) {
        return;
      }
    }

    _relayUploadBusy = true;
    try {
      final uploadMs = await _bridge.uploadRelayPreviewFrame(
        deviceId: device.deviceId,
        hostToken: hostToken,
        bytes: frame.bytes,
        width: frame.width,
        height: frame.height,
        timestampMs: frame.timestampMs,
      );
      if (!frameUnchanged) {
        // 保活重传不参与拥塞判断：它本来就是低频的。
        _noteUploadDuration(uploadMs);
      }
      _lastUploadedFrameTimestampMs = frame.timestampMs;
      _lastRelayUploadAtMs = DateTime.now().millisecondsSinceEpoch;
      _relayUploadRetryAfterMs = 0;
      if (_relayUploadFailureStreak > 0) {
        debugPrint(
          '[rdesk-host] 中继帧上传已恢复（此前连续失败 $_relayUploadFailureStreak 次）',
        );
        _relayUploadFailureStreak = 0;
      }
    } catch (error) {
      // 上传失败不应中断托管，但必须留下痕迹：此前这里静默吞掉异常，
      // 导致「设备显示在线、观看端却永远拉不到画面」无从排查。
      _relayUploadFailureStreak++;
      // 线性退避，上限 5 秒——仍远小于服务端 30 秒的帧 TTL，
      // 网络恢复后不会因为退避而错过保活窗口。
      final backoffMs = (_relayUploadFailureStreak * 500).clamp(500, 5000);
      _relayUploadRetryAfterMs =
          DateTime.now().millisecondsSinceEpoch + backoffMs;
      if (_relayUploadFailureStreak == 1 ||
          _relayUploadFailureStreak % 25 == 0) {
        debugPrint(
          '[rdesk-host] 中继帧上传失败（连续 $_relayUploadFailureStreak 次）: $error',
        );
      }
    } finally {
      _relayUploadBusy = false;
    }
  }

  /// 记录一次帧上传耗时，并据此自动调整采集档位。
  ///
  /// 观看端看到的延迟，主干是「被控端把这一帧推上去花了多久」。手机上行远小于
  /// 服务器带宽：1440 长边、质量 75 的整屏 JPEG 常有 200~400KB，12fps 就要
  /// 20~40Mbps 上行，蜂窝网根本喂不动。链路喂不动时帧不会丢，只会排队变旧——
  /// 画面看着还在动，延迟数字却一路涨到几百上千毫秒。
  ///
  /// 这里用上传耗时的滑动平均作为拥塞信号：持续追不上帧间隔就降档，
  /// 长期富余再升回去，上限不超过观看端明确要求的画质。
  void _noteUploadDuration(int uploadMs) {
    final previous = _uploadMsAverage;
    _uploadMsAverage = previous == null
        ? uploadMs.toDouble()
        : previous * 0.7 + uploadMs * 0.3;
    final average = _uploadMsAverage!;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lastShiftAtMs = _lastQualityShiftAtMs;
    if (lastShiftAtMs != null &&
        nowMs - lastShiftAtMs < _qualityShiftCooldown.inMilliseconds) {
      return;
    }

    final current = _effectiveQuality;
    double? next;
    if (average > _uploadSlowThresholdMs) {
      next = _lowerQualityTier(current);
    } else if (average < _uploadFastThresholdMs &&
        current < _requestedQuality) {
      next = _raiseQualityTier(current, ceiling: _requestedQuality);
    }
    if (next == null || next == current) {
      return;
    }

    _effectiveQuality = next;
    _lastQualityShiftAtMs = nowMs;
    _uploadMsAverage = null;
    debugPrint(
      '[rdesk-host] 上行平均耗时 ${average.round()}ms，采集档位 '
      '${(current * 100).round()}% → ${(next * 100).round()}%',
    );
    unawaited(_service.setCaptureQuality(quality: next, fps: null));
  }

  double? _lowerQualityTier(double current) {
    if (current > _qualityMedium) return _qualityMedium;
    if (current > _qualityLow) return _qualityLow;
    return null;
  }

  double? _raiseQualityTier(double current, {required double ceiling}) {
    final next = current < _qualityMedium ? _qualityMedium : _qualityHigh;
    return next > ceiling ? ceiling : next;
  }

  Future<bool> _applyCaptureQualityPayload(Map<String, dynamic> payload) async {
    final quality = (payload['quality'] as num?)?.toDouble();
    if (quality == null) {
      return false;
    }
    final fps = (payload['fps'] as num?)?.toInt();
    final ok = await _service.setCaptureQuality(
      quality: quality,
      fps: fps,
    );
    if (ok) {
      // 观看端的选择既是起点也是自适应升档的上限：用户挑了低画质就别偷偷升回去。
      _requestedQuality = quality;
      _effectiveQuality = quality;
      _uploadMsAverage = null;
      _lastQualityShiftAtMs = DateTime.now().millisecondsSinceEpoch;
      _lastRemoteAction = 'quality ${(quality * 100).round()}%';
      notifyListeners();
    }
    return ok;
  }

  Future<void> _pollRelayCommand() async {
    if (_relayCommandBusy) {
      return;
    }
    final device = _localDevice;
    final hostToken = _relayHostToken;
    if (device == null || hostToken == null || hostToken.isEmpty) {
      return;
    }
    // 服务器不可达时轮询会立刻失败返回，60ms 的定时器随即再发一次——
    // 断网期间就是每秒十几次连接尝试。与帧上传一样做线性退避。
    if (DateTime.now().millisecondsSinceEpoch < _relayCommandRetryAfterMs) {
      return;
    }

    _relayCommandBusy = true;
    try {
      final command = await _bridge.pollHostedCommand(
        deviceId: device.deviceId,
        hostToken: hostToken,
      );
      // 请求本身成功即说明链路恢复，退避清零；队列空（返回 null）也算成功。
      _relayCommandFailureStreak = 0;
      _relayCommandRetryAfterMs = 0;
      if (command == null || command.commandId.isEmpty) {
        return;
      }

      var ok = false;
      String? text;
      switch (command.kind) {
        case 'incoming_request':
          final deviceId = command.payload['deviceId'] as String?;
          final hostname = command.payload['hostname'] as String? ?? '未知设备';
          final peerOs = command.payload['peerOs'] as String? ?? '未知';
          if (deviceId != null) {
            final ctx = rootNavigatorKey.currentContext;
            if (ctx != null && ctx.mounted) {
              // ignore: use_build_context_synchronously
              final action = await showIncomingConnectionDialog(
                ctx,
                IncomingConnectionRequest(
                  peerId: deviceId,
                  peerHostname: hostname,
                  peerPlatform: peerOs,
                  requestedAt: DateTime.now(),
                ),
              );
              ok = action == IncomingConnectionAction.accept;
            }
          }
          break;
        case 'trust':
          final deviceId = command.payload['deviceId'] as String?;
          final hostname = command.payload['hostname'] as String?;
          final peerOs = command.payload['peerOs'] as String?;
          if (deviceId != null && hostname != null && peerOs != null) {
            // Auto-wake screen when a remote viewer connects via relay
            try {
              await _service.wakeScreen();
            } catch (_) {}
            await _bridge.trustIncomingViewer(
              deviceId: deviceId,
              hostname: hostname,
              peerOs: peerOs,
            );
            await _registerPreviewHost();
            ok = true;
          }
          break;
        case 'tap':
          final x = (command.payload['x'] as num?)?.toDouble();
          final y = (command.payload['y'] as num?)?.toDouble();
          if (x != null && y != null) {
            _lastRemoteTap = '${(x * 100).round()}%, ${(y * 100).round()}%';
            notifyListeners();
            ok = await _service.showRemoteTapIndicator(
              normalizedX: x,
              normalizedY: y,
            );
          }
          break;
        case 'action':
          final action = command.payload['action'] as String?;
          if (action != null && action.isNotEmpty) {
            _lastRemoteAction = action;
            notifyListeners();
            if (action == 'wake_screen') {
              ok = await _service.wakeScreen();
            } else {
              ok = await _service.performRemoteAction(action);
            }
          }
          break;
        case 'long_press':
          final x = (command.payload['x'] as num?)?.toDouble();
          final y = (command.payload['y'] as num?)?.toDouble();
          if (x != null && y != null) {
            _lastRemoteGesture =
                'long_press ${(x * 100).round()}%, ${(y * 100).round()}%';
            notifyListeners();
            ok = await _service.performRemoteLongPress(
              normalizedX: x,
              normalizedY: y,
            );
          }
          break;
        case 'drag':
          final startX = (command.payload['startX'] as num?)?.toDouble();
          final startY = (command.payload['startY'] as num?)?.toDouble();
          final endX = (command.payload['endX'] as num?)?.toDouble();
          final endY = (command.payload['endY'] as num?)?.toDouble();
          if (startX != null &&
              startY != null &&
              endX != null &&
              endY != null) {
            _lastRemoteGesture =
                'drag ${(startX * 100).round()}%, ${(startY * 100).round()}% -> ${(endX * 100).round()}%, ${(endY * 100).round()}%';
            notifyListeners();
            ok = await _service.performRemoteDrag(
              startX: startX,
              startY: startY,
              endX: endX,
              endY: endY,
            );
          }
          break;
        case 'drag_path':
          final rawPoints = command.payload['points'] as List<dynamic>?;
          if (rawPoints != null && rawPoints.length >= 2) {
            final points = rawPoints
                .map((p) => [(p as List<dynamic>)[0] as double, p[1] as double])
                .toList();
            _lastRemoteGesture = 'drag_path ${points.length} points';
            notifyListeners();
            ok = await _service.performRemoteDragPath(points);
          }
          break;
        case 'text':
          final input = command.payload['text'] as String?;
          if (input != null) {
            _lastRemoteText = input;
            notifyListeners();
            ok = await _service.performRemoteTextInput(input);
          }
          break;
        case 'clipboard_set':
          final input = command.payload['text'] as String?;
          if (input != null) {
            _lastRemoteClipboard = input;
            notifyListeners();
            ok = await _service.setClipboardText(input);
          }
          break;
        case 'clipboard_get':
          text = await _service.getClipboardText();
          _lastRemoteClipboard = text;
          notifyListeners();
          ok = true;
          break;
        case 'quality':
          ok = await _applyCaptureQualityPayload(command.payload);
          break;
      }

      await _bridge.submitHostedCommandResult(
        deviceId: device.deviceId,
        hostToken: hostToken,
        commandId: command.commandId,
        ok: ok,
        text: text,
      );
    } catch (_) {
      // Ignore transient relay command failures and continue polling.
      _relayCommandFailureStreak++;
      final backoffMs = (_relayCommandFailureStreak * 250).clamp(250, 3000);
      _relayCommandRetryAfterMs =
          DateTime.now().millisecondsSinceEpoch + backoffMs;
    } finally {
      _relayCommandBusy = false;
    }
  }
}
