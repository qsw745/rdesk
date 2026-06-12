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
  static const _previewPollInterval = Duration(milliseconds: 80);
  static const _relayCommandPollInterval = Duration(milliseconds: 60);

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
  bool _relayCommandBusy = false;
  bool _relayUploadBusy = false;
  int? _lastUploadedFrameTimestampMs;
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

  Future<void> initialize({bool enabled = true}) async {
    if (!enabled) {
      return;
    }
    _localDevice = await _bridge.getLocalDeviceInfo();
    final prefs = await SharedPreferences.getInstance();
    _guardModeEnabled = prefs.getBool(_guardModeEnabledKey) ?? false;
    await _run(() async {
      _state = await _service.getState();
      if (_guardModeEnabled && _state.hasPermission && !_state.isRunning) {
        _state = await _service.startHosting();
      }
      if (_state.isRunning) {
        await _service.setKeepScreenOn(enabled: true);
        _ensurePreviewPolling();
        await _ensureLanRelay();
        await _registerPreviewHost();
        _ensureRelayCommandPolling();
      }
    }, clearError: false);
  }

  Future<void> requestPermission() async {
    await _run(() async {
      _state = await _service.requestPermission();
      if (_guardModeEnabled && _state.hasPermission && !_state.isRunning) {
        _state = await _service.startHosting();
        await _service.setKeepScreenOn(enabled: true);
        _ensurePreviewPolling();
        await _ensureLanRelay();
        await _registerPreviewHost();
        _ensureRelayCommandPolling();
      }
    });
  }

  Future<void> startHosting() async {
    await _run(() async {
      _state = await _service.startHosting();
      // Keep screen on while hosting to prevent sleep
      await _service.setKeepScreenOn(enabled: true);
      _ensurePreviewPolling();
      await _ensureLanRelay();
      await _registerPreviewHost();
      _ensureRelayCommandPolling();
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
        final oldToken = _relayHostToken;
        _relayHostToken = null;
        _lastUploadedFrameTimestampMs = null;
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
      if (_state.isRunning) {
        _ensurePreviewPolling();
        _ensureRelayCommandPolling();
      }
    }, clearError: false);
  }

  Future<void> openAccessibilitySettings() =>
      _service.openAccessibilitySettings();

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
      _lastUploadedFrameTimestampMs = null;

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
      return;
    }
    unawaited(_pollPreviewFrame());
    _previewTimer = Timer.periodic(
      _previewPollInterval,
      (_) => unawaited(_pollPreviewFrame()),
    );
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
    _lastUploadedFrameTimestampMs = null;
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

  Future<void> _uploadRelayFrame(AndroidHostFrame frame) async {
    final device = _localDevice;
    final hostToken = _relayHostToken;
    if (device == null ||
        hostToken == null ||
        hostToken.isEmpty ||
        _relayUploadBusy ||
        frame.bytes.isEmpty ||
        _lastUploadedFrameTimestampMs == frame.timestampMs) {
      return;
    }

    _relayUploadBusy = true;
    try {
      await _bridge.uploadRelayPreviewFrame(
        deviceId: device.deviceId,
        hostToken: hostToken,
        bytes: frame.bytes,
        width: frame.width,
        height: frame.height,
        timestampMs: frame.timestampMs,
      );
      _lastUploadedFrameTimestampMs = frame.timestampMs;
    } catch (_) {
      // Keep hosting alive on transient relay upload failures.
    } finally {
      _relayUploadBusy = false;
    }
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

    _relayCommandBusy = true;
    try {
      final command = await _bridge.pollHostedCommand(
        deviceId: device.deviceId,
        hostToken: hostToken,
      );
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
    } finally {
      _relayCommandBusy = false;
    }
  }
}
