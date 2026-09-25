import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';

import '../models/device.dart';
import '../services/rdesk_bridge_service.dart';
import '../services/android_host_service.dart'; // Reuse AndroidHostState / AndroidHostFrame
import '../services/desktop_host_service.dart';
import '../utils/router.dart';
import '../widgets/incoming_connection_dialog.dart';

/// Host provider for desktop platforms (macOS, Windows, Linux).
///
/// Mirrors [AndroidHostProvider] but uses [DesktopHostService] for
/// screen capture and input simulation instead of Android MethodChannel.
class DesktopHostProvider extends ChangeNotifier {
  final _bridge = RdeskBridgeService.instance;
  final _service = DesktopHostService.instance;
  final int lanPort;
  DesktopHostProvider({this.lanPort = 21116});

  bool _hostingEnabled = false;
  bool _disposed = false;
  int _hostGeneration = 0;
  int _captureGeneration = 0;
  Future<void> _hostTransition = Future<void>.value();
  final _clock = Stopwatch()..start();
  static const screenLeaseMs = 10000;
  final Map<String, int> _lanScreenLeases = {};
  int _relayLeaseUntil = 0;
  int _relayViewers = 0;
  int _relayCaptureEpoch = 0;
  bool _relayDemandBusy = false;
  Timer? _demandTimer;
  Timer? _relayDemandTimer;
  RelayFrameUpload? _frameUpload;
  int _uploadedFrames = 0;
  String? _relayDemandError;

  bool get hostingEnabled => _hostingEnabled && !_disposed;
  bool get captureRunning => _service.captureRunning;
  int get activeViewerCount =>
      _lanScreenLeases.length +
      (_clock.elapsedMilliseconds < _relayLeaseUntil ? _relayViewers : 0);
  bool get _hasRelayViewer =>
      hostingEnabled &&
      _relayViewers > 0 &&
      _clock.elapsedMilliseconds < _relayLeaseUntil;
  bool get _needsCapture =>
      hostingEnabled &&
      (_lanScreenLeases.values
              .any((until) => until > _clock.elapsedMilliseconds) ||
          _hasRelayViewer);
  bool _hostCurrent(int generation) =>
      hostingEnabled && generation == _hostGeneration;
  bool _captureCurrent(int generation) =>
      _needsCapture && generation == _captureGeneration;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  AndroidHostState _state = const AndroidHostState(
    state: 'idle',
    hasPermission: true,
    isRunning: false,
    accessibilityEnabled: true,
    overlayEnabled: true,
    notificationsEnabled: true,
    batteryOptimizationIgnored: true,
    manufacturer: 'desktop',
  );
  AndroidHostFrame? _previewFrame;
  bool _busy = false;
  String? _error;
  Timer? _previewTimer;
  Timer? _registrationTimer;
  Timer? _relayCommandTimer;
  Timer? _hostRecoveryTimer;
  HttpServer? _lanRelayServer;
  String? _lanRelayEndpoint;
  DeviceInfo? _localDevice;
  String? _relayHostToken;
  DateTime? _lastHostRegistrationAt;
  String? _lastHostRegistrationError;
  int _registrationAttempts = 0;
  bool _relayCommandBusy = false;
  bool _relayUploadBusy = false;
  bool _relayRegisterBusy = false;
  int? _lastUploadedFrameTimestampMs;
  int _emptyFrameStreak = 0;
  bool _captureInFlight = false;
  DateTime? _lastCaptureStallPromptAt;
  // LAN session tokens issued via /session/trust (password-authenticated).
  final Set<String> _lanSessionTokens = {};

  AndroidHostState get state => _state;
  AndroidHostFrame? get previewFrame => _previewFrame;
  String? get lanRelayEndpoint => _lanRelayEndpoint;
  bool get busy => _busy;
  String? get error => _error ?? _relayDemandError;
  bool get hostRegistered => (_relayHostToken?.isNotEmpty ?? false);
  DateTime? get lastHostRegistrationAt => _lastHostRegistrationAt;
  String? get hostRegistrationError => _lastHostRegistrationError;
  int get registrationAttempts => _registrationAttempts;
  String? get localDeviceId => _localDevice?.deviceId;
  bool get canDisconnectViewers =>
      hostingEnabled &&
      activeViewerCount > 0 &&
      _localDevice != null &&
      (_relayHostToken?.isNotEmpty ?? false);

  Future<void> initialize({bool enabled = true}) async {
    if (!enabled) return;
    await _ensureLocalDeviceInfo();
    await _run(() async {
      _state = await _service.getState();
      await _refreshPermissionState();
    }, clearError: false);
    _ensureHostRecoveryLoop();
  }

  Future<void> startHosting() {
    if (_disposed || hostingEnabled) return _hostTransition;
    _hostingEnabled = true;
    final generation = ++_hostGeneration;
    _hostTransition = _hostTransition.then((_) => _run(() async {
          if (!_hostCurrent(generation)) return;
          await _ensureLocalDeviceInfo();
          if (!_hostCurrent(generation)) return;
          final state = await _service.startHosting();
          if (!_hostCurrent(generation)) return;
          _state = state;
          _ensureRegistrationTimer();
          _ensureDemandPolling();
          try {
            await _ensureLanRelay();
          } catch (e) {
            debugPrint('[RDesk] DesktopHost: LAN relay failed: $e');
          }
          if (!_hostCurrent(generation)) return;
          await _registerPreviewHost();
          if (_hostCurrent(generation)) _ensureRelayCommandPolling();
        }));
    return _hostTransition;
  }

  Future<void> stopHosting() {
    // Revoke intent synchronously, before any outstanding async work resumes.
    _hostingEnabled = false;
    ++_hostGeneration;
    _stopDemandPolling();
    _registrationTimer?.cancel();
    _registrationTimer = null;
    _relayCommandTimer?.cancel();
    _relayCommandTimer = null;
    _hostTransition = _hostTransition.then((_) => _run(() async {
          _state = await _service.stopHosting();
          final oldToken = _relayHostToken;
          _relayHostToken = null;
          _lastHostRegistrationAt = null;
          await _closeLanRelay();
          if (_localDevice != null && oldToken != null) {
            try {
              await _bridge
                  .unregisterPreviewHost(_localDevice!.deviceId,
                      hostToken: oldToken)
                  .timeout(const Duration(seconds: 3));
            } catch (_) {}
          }
        }));
    return _hostTransition;
  }

  void _stopDemandPolling() {
    _demandTimer?.cancel();
    _demandTimer = null;
    _relayDemandTimer?.cancel();
    _relayDemandTimer = null;
    _lanScreenLeases.clear();
    _lanSessionTokens.clear();
    _relayLeaseUntil = 0;
    _relayViewers = 0;
    _relayDemandError = null;
    _stopCapture();
  }

  void _stopCapture() {
    ++_captureGeneration;
    _previewTimer?.cancel();
    _previewTimer = null;
    _frameUpload?.cancel();
    _frameUpload = null;
    _previewFrame = null;
    _lastUploadedFrameTimestampMs = null;
    _emptyFrameStreak = 0;
    _error = null;
    unawaited(_service.stopCapture().catchError((Object e) {
      debugPrint('[RDeskCapture] stop failed: $e');
    }));
    debugPrint('[RDeskCapture] stopped uploaded=$_uploadedFrames');
    notifyListeners();
  }

  void _ensureDemandPolling() {
    if (!hostingEnabled) return;
    _demandTimer ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      _lanScreenLeases
          .removeWhere((_, until) => until <= _clock.elapsedMilliseconds);
      _syncCaptureDemand();
    });
    _relayDemandTimer ??= Timer.periodic(
        const Duration(seconds: 1), (_) => unawaited(_pollScreenDemand()));
    unawaited(_pollScreenDemand());
  }

  void _syncCaptureDemand() {
    if (!_hasRelayViewer) {
      _frameUpload?.cancel();
      _frameUpload = null;
    } else {
      _frameUpload ??= RelayFrameUpload();
    }
    if (!_needsCapture) {
      if (_previewTimer != null || captureRunning || _previewFrame != null) {
        _stopCapture();
      }
      return;
    }
    if (_previewTimer == null || !captureRunning) _ensurePreviewPolling();
  }

  Future<void> _pollScreenDemand() async {
    final generation = _hostGeneration;
    final device = _localDevice;
    final token = _relayHostToken;
    if (!hostingEnabled ||
        _relayDemandBusy ||
        device == null ||
        token == null) {
      return;
    }
    _relayDemandBusy = true;
    final sentAt = _clock.elapsedMilliseconds;
    try {
      final demand = await _bridge.pollHostedScreenDemand(
          deviceId: device.deviceId, hostToken: token);
      if (!_hostCurrent(generation) || token != _relayHostToken) return;
      if (_relayCaptureEpoch != demand.epoch) {
        // A new audience must never receive a frame captured for an old one.
        _stopCapture();
        _relayCaptureEpoch = demand.epoch;
      }
      _relayViewers = demand.viewers;
      // Deduct response time conservatively; a slow response cannot extend a lease.
      _relayLeaseUntil = sentAt + demand.expiresInMs.clamp(0, screenLeaseMs);
      _relayDemandError = null;
      _syncCaptureDemand();
      notifyListeners();
    } catch (e) {
      if (!_hostCurrent(generation)) return;
      if (e is HttpException && e.message.contains('需更新')) {
        _relayDemandError = e.message;
        notifyListeners();
      }
      // Keep the last proven lease only until its original finite deadline.
      _syncCaptureDemand();
    } finally {
      _relayDemandBusy = false;
    }
  }

  /// Reset permission denied latch and restart capture polling.
  /// Call after the user grants screen recording permission in Settings.
  Future<void> retryAfterPermissionGrant() async {
    await _service.resetPermissionDenied();
    _error = null;
    _emptyFrameStreak = 0;
    await _refreshPermissionState();
    if (hostingEnabled) {
      _syncCaptureDemand();
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    await _run(() async {
      final generation = _hostGeneration;
      final state = await _service.getState();
      if (!_hostCurrent(generation)) return;
      _state = state;
      await _refreshPermissionState();
      if (_hostCurrent(generation)) {
        _syncCaptureDemand();
        _ensureRelayCommandPolling();
        _ensureRegistrationTimer();
      }
    }, clearError: false);
  }

  @override
  void dispose() {
    _hostingEnabled = false;
    ++_hostGeneration;
    _disposed = true;
    _stopDemandPolling();
    unawaited(_service.stopHosting().catchError((Object _) => _state));
    _previewTimer?.cancel();
    _registrationTimer?.cancel();
    _relayCommandTimer?.cancel();
    _hostRecoveryTimer?.cancel();
    unawaited(_closeLanRelay(notify: false));
    super.dispose();
  }

  Future<bool> disconnectCurrentViewer() async {
    final device = _localDevice;
    final hostToken = _relayHostToken;
    if (!hostingEnabled || device == null) {
      return false;
    }

    final generation = ++_hostGeneration;
    _stopDemandPolling();
    await _run(() async {
      // 1) Unregister from relay to remove preview entry AND all viewer
      //    sessions atomically.  Relay-connected viewers will get 401.
      if (hostToken != null && hostToken.isNotEmpty) {
        try {
          await _bridge.unregisterPreviewHost(
            device.deviceId,
            hostToken: hostToken,
          );
        } catch (_) {
          try {
            await _bridge.disconnectHostedViewers(
              deviceId: device.deviceId,
              hostToken: hostToken,
            );
          } catch (_) {}
        }
      }

      // 2) Close LAN relay to cut direct connections
      await _closeLanRelay();
      _relayHostToken = null;
      _lastUploadedFrameTimestampMs = null;

      // 3) Re-open only if the user still wants hosting.
      if (!_hostCurrent(generation)) return;
      _ensureDemandPolling();
      await _ensureLanRelay();
      await _registerPreviewHost();
      _ensureRelayCommandPolling();
    });
    return _error == null;
  }

  // ---------- internal ----------

  Future<void> _run(
    Future<void> Function() action, {
    bool clearError = true,
  }) async {
    _busy = true;
    if (clearError) _error = null;
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

  void _ensureHostRecoveryLoop() {
    _hostRecoveryTimer?.cancel();
    if (_disposed || !Platform.isMacOS) return;
    _hostRecoveryTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => unawaited(_maintainHostAvailability()),
    );
    unawaited(_maintainHostAvailability());
  }

  Future<void> _maintainHostAvailability() async {
    if (!hostingEnabled || _busy) return;
    final generation = _hostGeneration;
    _syncCaptureDemand();
    if (_lanRelayServer == null) {
      try {
        await _ensureLanRelay();
      } catch (_) {}
    }
    if (!_hostCurrent(generation)) return;
    _ensureRegistrationTimer();
    _ensureDemandPolling();
    if (_relayHostToken == null) await _registerPreviewHost();
  }

  void _ensureRegistrationTimer() {
    if (!hostingEnabled || _registrationTimer != null) return;
    _registrationTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_registerPreviewHost()),
    );
  }

  void _ensurePreviewPolling() {
    if (!_needsCapture) return;
    _previewTimer?.cancel();
    final generation = ++_captureGeneration;
    _frameUpload?.cancel();
    _frameUpload = _hasRelayViewer ? RelayFrameUpload() : null;
    unawaited(_service.startCapture().then((_) {
      if (_captureCurrent(generation)) unawaited(_pollPreviewFrame());
    }).catchError((Object e) {
      if (_captureCurrent(generation)) {
        _error = _formatError(e);
        notifyListeners();
      }
    }));
    _previewTimer = Timer.periodic(const Duration(milliseconds: 100),
        (_) => unawaited(_pollPreviewFrame()));
    debugPrint(
        '[RDeskCapture] start viewers=$activeViewerCount generation=$generation');
  }

  Future<void> _pollPreviewFrame() async {
    // Prevent overlapping captures — SCKit doesn't handle concurrent calls well.
    if (!_needsCapture || _captureInFlight) return;
    final generation = _captureGeneration;
    _captureInFlight = true;
    try {
      final frame = await _service.getLatestFrame();
      if (!_captureCurrent(generation)) return;
      if (frame != null) {
        _emptyFrameStreak = 0;
        if (_error != null) {
          _error = null;
        }
        final changed = _previewFrame?.timestampMs != frame.timestampMs ||
            _previewFrame?.bytes.length != frame.bytes.length;
        _previewFrame = frame;
        if (changed) notifyListeners();
        if ((_relayHostToken == null || _relayHostToken!.isEmpty) &&
            _state.isRunning) {
          unawaited(_registerPreviewHost());
        }
        await _uploadRelayFrame(frame, generation);
      } else if (_needsCapture) {
        _emptyFrameStreak++;
        if (_emptyFrameStreak >= 8) {
          final now = DateTime.now();
          final shouldPrompt = _lastCaptureStallPromptAt == null ||
              now.difference(_lastCaptureStallPromptAt!) >
                  const Duration(seconds: 20);
          if (shouldPrompt) {
            _lastCaptureStallPromptAt = now;
            if (_error != '未获取到可用的桌面画面，请检查屏幕录制权限。') {
              _error = '未获取到可用的桌面画面，请检查屏幕录制权限。';
              notifyListeners();
            }
            await _refreshPermissionState();
          }
          _emptyFrameStreak = 0;
        }
      }
    } catch (error) {
      if (!_captureCurrent(generation)) return;
      final message = _formatError(error);
      if (_error != message) {
        _error = message;
        notifyListeners();
      }
      if (error is DesktopPermissionException &&
          (error.code == 'screen_recording_denied')) {
        // Retry only while a current authenticated screen lease remains.
        // Native side uses a 30s cooldown before retrying SCKit,
        // so we don't need to stop polling. The native call returns
        // immediately with PERMISSION_DENIED during cooldown (no popup).
        // Just log once and let the polling continue — it will auto-recover
        // once the user grants permission in System Settings.
        debugPrint('[RDesk] Screen recording denied — native cooldown active, '
            'will auto-retry in ~30s.');
      }
    } finally {
      _captureInFlight = false;
    }
  }

  void _ensureRelayCommandPolling() {
    _relayCommandTimer?.cancel();
    if (!hostingEnabled || _relayHostToken == null || _localDevice == null) {
      return;
    }
    unawaited(_pollRelayCommand());
    _relayCommandTimer = Timer.periodic(
      const Duration(milliseconds: 150),
      (_) => unawaited(_pollRelayCommand()),
    );
  }

  // ---------- LAN HTTP relay (same as Android) ----------

  Future<void> _ensureLanRelay() async {
    if (!hostingEnabled) return;
    final generation = _hostGeneration;
    if (_lanRelayServer != null) {
      debugPrint('[RDesk] LAN relay already running at $_lanRelayEndpoint');
      return;
    }

    debugPrint('[RDesk] LAN relay: binding to 0.0.0.0:$lanPort ...');
    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.anyIPv4, lanPort);
    } catch (_) {
      // Port occupied, fall back to random port
      debugPrint(
          '[RDesk] LAN relay: port $lanPort occupied, using random port');
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    if (!_hostCurrent(generation)) {
      await server.close(force: true);
      return;
    }
    _lanRelayServer = server;
    final localIp = await _resolveLocalIpv4();
    if (!_hostCurrent(generation)) {
      await _closeLanRelay();
      return;
    }
    debugPrint('[RDesk] LAN relay: localIp=$localIp, port=${server.port}');
    _lanRelayEndpoint = localIp != null
        ? '$localIp:${server.port}'
        : '127.0.0.1:${server.port}';
    debugPrint('[RDesk] LAN relay endpoint: $_lanRelayEndpoint');
    notifyListeners();

    unawaited(
      server.forEach((request) async {
        final response = request.response;
        response.headers.set('Cache-Control', 'no-store');

        if (!_hostCurrent(generation)) {
          response.statusCode = HttpStatus.serviceUnavailable;
          await response.close();
          return;
        }
        // --- Unauthenticated endpoints ---

        if (request.uri.path == '/health') {
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(<String, Object?>{
            'state': _state.state,
            'running': hostingEnabled,
            'hostingEnabled': hostingEnabled,
            'activeViewers': activeViewerCount,
            'captureRunning': captureRunning,
            'uploadedFrames': _uploadedFrames,
            'capture': await _service.captureDiagnostics(),
            'hasPermission': _state.hasPermission,
            'hasFrame': _previewFrame != null,
            'endpoint': _lanRelayEndpoint,
            'platform': Platform.operatingSystem,
          }));
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
          if (!_hostCurrent(generation)) {
            await response.close();
            return;
          }
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

        if ((request.uri.path == '/session/close' ||
                request.uri.path == '/session/screen/stop') &&
            request.method == 'POST') {
          if (request.uri.path == '/session/close') {
            _lanSessionTokens.remove(token);
          }
          _lanScreenLeases.remove(token);
          _syncCaptureDemand();
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode({'ok': true}));
          await response.close();
          return;
        }

        if (request.uri.path == '/frame.jpg' && request.method == 'GET') {
          _lanScreenLeases[token] = _clock.elapsedMilliseconds + screenLeaseMs;
          _syncCaptureDemand();
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

        if (request.uri.path == '/displays' && request.method == 'GET') {
          final displays = await _service.listDisplays();
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(displays));
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
          final ok = await _service.performRemoteTap(
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
          debugPrint('[RDesk] LAN remote action received: $action');
          final ok = await _service.performRemoteAction(action);
          debugPrint('[RDesk] LAN remote action completed: $action ok=$ok');
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
          final ok = await _service.setClipboardText(text);
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(<String, Object?>{'ok': ok}));
          await response.close();
          return;
        }

        if (request.uri.path == '/clipboard/get' && request.method == 'GET') {
          final text = await _service.getClipboardText();
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(<String, Object?>{'text': text}));
          await response.close();
          return;
        }

        if (request.uri.path == '/settings/quality' &&
            request.method == 'POST') {
          final body = await utf8.decoder.bind(request).join();
          final payload = jsonDecode(body) as Map<String, dynamic>;
          final quality = (payload['quality'] as num?)?.toDouble();
          if (quality != null) {
            _service.setJpegQuality(quality);
          }
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(<String, Object?>{
            'ok': true,
            'quality': _service.jpegQuality,
          }));
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
    _lanScreenLeases.clear();
    _syncCaptureDemand();
    if (server != null) {
      // Give in-flight requests a moment to receive 401 before closing.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await server.close(force: true);
    }
    if (notify) notifyListeners();
  }

  Future<String?> _resolveLocalIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final candidates = <({int score, String address})>[];
      for (final interface in interfaces) {
        final name = interface.name.toLowerCase();
        final score = switch (name) {
          final v
              when v.contains('en') ||
                  v.contains('eth') ||
                  v.contains('wlan') ||
                  v.contains('wifi') =>
            0,
          final v
              when v.contains('utun') ||
                  v.contains('bridge') ||
                  v.contains('lo') =>
            3,
          _ => 1,
        };
        for (final address in interface.addresses) {
          if (address.isLoopback || !address.address.contains('.')) continue;
          candidates.add((score: score, address: address.address));
        }
      }
      if (candidates.isEmpty) return null;
      candidates.sort((a, b) => a.score.compareTo(b.score));
      return candidates.first.address;
    } catch (_) {
      // Network interface probing can fail under restrictive desktop sandbox
      // policies. Fallback to loopback endpoint so host registration still runs.
      return null;
    }
  }

  // ---------- signaling server registration ----------

  Future<void> _registerPreviewHost() async {
    if (!hostingEnabled || _relayRegisterBusy) return;
    _relayRegisterBusy = true;
    try {
      await _registerPreviewHostInner();
    } finally {
      _relayRegisterBusy = false;
    }
  }

  Future<void> _registerPreviewHostInner() async {
    final generation = _hostGeneration;
    _ensureRegistrationTimer();
    final device = await _ensureLocalDeviceInfo();
    if (device == null || !_hostCurrent(generation)) return;
    final endpoint = (_lanRelayEndpoint?.trim().isNotEmpty ?? false)
        ? _lanRelayEndpoint!
        : '127.0.0.1:0';
    _registrationAttempts++;

    // Registration is a heartbeat, independent of screen frames.
    final password = await _bridge.getActiveAccessPassword();
    final settings = await _bridge.loadSettings();
    final trustedViewerIds = await _bridge.listTrustedIncomingViewerIds();
    final authToken = await _bridge.getAccountToken();

    if (!_hostCurrent(generation)) return;
    final oldToken = _relayHostToken;
    String? hostToken;
    try {
      hostToken = await _bridge.registerPreviewHost(
        deviceId: device.deviceId,
        endpoint: endpoint,
        platform: device.os,
        hostname: device.hostname,
        password: password,
        autoAccept: settings.autoAccept,
        trustedViewerIds: trustedViewerIds,
        authToken: authToken,
        hostToken: _relayHostToken,
        onDemandCapture: true,
      );
      if (!_hostCurrent(generation)) {
        if (hostToken != null) {
          try {
            await _bridge.unregisterPreviewHost(device.deviceId,
                hostToken: hostToken);
          } catch (_) {}
        }
        return;
      }
    } catch (error) {
      final message = _formatError(error);
      if (!_hostCurrent(generation)) return;
      final formatted = '共享服务注册失败：$message';
      _lastHostRegistrationError = formatted;
      debugPrint(
          '[RDesk] register failed: $message (oldToken=${_tokenPreview(oldToken)})');
      if (_error != formatted) {
        _error = formatted;
        notifyListeners();
      }
      return;
    }
    debugPrint(
        '[RDesk] register response: hostToken=${_tokenPreview(hostToken)} '
        'oldToken=${_tokenPreview(oldToken)}');
    if (hostToken != null && hostToken.isNotEmpty) {
      _relayHostToken = hostToken;
      _lastHostRegistrationAt = DateTime.now();
      _lastHostRegistrationError = null;
      if (_error?.startsWith('共享服务注册失败：') == true) {
        _error = null;
      }
    } else {
      debugPrint('[RDesk] register: server returned empty/null host_token!');
      const formatted = '共享服务注册失败：服务端未返回 host_token';
      _lastHostRegistrationError = formatted;
      if (_error != formatted) {
        _error = formatted;
        notifyListeners();
      }
    }
    _ensureRelayCommandPolling();
  }

  Future<void> _uploadRelayFrame(AndroidHostFrame frame, int generation) async {
    final device = _localDevice;
    final hostToken = _relayHostToken;
    final upload = _frameUpload;
    if (!_captureCurrent(generation) ||
        !_hasRelayViewer ||
        upload == null ||
        device == null ||
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
        captureEpoch: _relayCaptureEpoch,
        upload: upload,
      );
      if (!_captureCurrent(generation) || !_hasRelayViewer) return;
      _uploadedFrames++;
      _lastUploadedFrameTimestampMs = frame.timestampMs;
    } catch (_) {
      upload.cancel();
      if (identical(_frameUpload, upload)) _frameUpload = null;
    } finally {
      _relayUploadBusy = false;
    }
  }

  Future<void> _pollRelayCommand() async {
    if (!hostingEnabled || _relayCommandBusy) return;
    final generation = _hostGeneration;
    final device = _localDevice;
    final hostToken = _relayHostToken;
    if (device == null || hostToken == null || hostToken.isEmpty) return;

    _relayCommandBusy = true;
    try {
      final command = await _bridge.pollHostedCommand(
        deviceId: device.deviceId,
        hostToken: hostToken,
      );
      if (!_hostCurrent(generation) ||
          hostToken != _relayHostToken ||
          command == null ||
          command.commandId.isEmpty) {
        return;
      }

      debugPrint('[RDesk] _pollRelayCommand: got command kind=${command.kind} '
          'id=${command.commandId}');
      var ok = false;
      String? text;
      switch (command.kind) {
        case 'incoming_request':
          final deviceId = command.payload['deviceId'] as String?;
          final hostname = command.payload['hostname'] as String? ?? '未知设备';
          final peerOs = command.payload['peerOs'] as String? ?? '未知';
          if (deviceId != null) {
            await _service.activateAppWindow();
            var ctx = _activeRootContext();
            ctx ??= await _waitForRootContext();
            if (ctx != null) {
              // ignore: use_build_context_synchronously
              final action = await showIncomingConnectionDialog(
                // ignore: use_build_context_synchronously
                ctx,
                IncomingConnectionRequest(
                  peerId: deviceId,
                  peerHostname: hostname,
                  peerPlatform: peerOs,
                  requestedAt: DateTime.now(),
                ),
                presentation: IncomingConnectionPresentation.desktopBottomRight,
              );
              ok = action == IncomingConnectionAction.accept;
              // Permission probing may be conservative on newer macOS.
              // Accepting authorizes the session; only frame demand can capture.
              if (!_hostCurrent(generation)) return;
            } else {
              text = 'host_ui_unavailable';
            }
          }
          break;
        case 'trust':
          final deviceId = command.payload['deviceId'] as String?;
          final hostname = command.payload['hostname'] as String?;
          final peerOs = command.payload['peerOs'] as String?;
          if (deviceId != null && hostname != null && peerOs != null) {
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
            ok =
                await _service.performRemoteTap(normalizedX: x, normalizedY: y);
          }
          break;
        case 'action':
          final action = command.payload['action'] as String?;
          if (action != null && action.isNotEmpty) {
            debugPrint('[RDesk] Relay remote action received: $action');
            ok = await _service.performRemoteAction(action);
            debugPrint('[RDesk] Relay remote action completed: $action ok=$ok');
          }
          break;
        case 'long_press':
          final x = (command.payload['x'] as num?)?.toDouble();
          final y = (command.payload['y'] as num?)?.toDouble();
          if (x != null && y != null) {
            ok = await _service.performRemoteLongPress(
                normalizedX: x, normalizedY: y);
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
            ok = await _service.performRemoteDrag(
              startX: startX,
              startY: startY,
              endX: endX,
              endY: endY,
            );
          }
          break;
        case 'text':
          final input = command.payload['text'] as String?;
          if (input != null) {
            ok = await _service.performRemoteTextInput(input);
          }
          break;
        case 'clipboard_set':
          final input = command.payload['text'] as String?;
          if (input != null) {
            ok = await _service.setClipboardText(input);
          }
          break;
        case 'clipboard_get':
          text = await _service.getClipboardText();
          ok = true;
          break;
        case 'list_displays':
          final displays = await _service.listDisplays();
          text = jsonEncode(displays);
          ok = true;
          break;
      }

      debugPrint(
          '[RDesk] _pollRelayCommand: executing kind=${command.kind} result=$ok');
      if (!_hostCurrent(generation)) return;
      await _bridge.submitHostedCommandResult(
        deviceId: device.deviceId,
        hostToken: hostToken,
        commandId: command.commandId,
        ok: ok,
        text: text,
      );
    } catch (e) {
      debugPrint('[RDesk] _pollRelayCommand ERROR: $e');
    } finally {
      _relayCommandBusy = false;
    }
  }

  Future<void> openAccessibilitySettings() =>
      _service.openAccessibilitySettings();

  Future<void> openScreenRecordingSettings() async {
    await _service.openScreenRecordingSettings();
    // After opening settings, user likely grants permission.
    // Reset the denied latch so next capture attempt will retry.
    await _service.resetPermissionDenied();
    _emptyFrameStreak = 0;
  }

  BuildContext? _activeRootContext() {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      return null;
    }
    return ctx;
  }

  Future<BuildContext?> _waitForRootContext({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var ctx = _activeRootContext();
    while (ctx == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      ctx = _activeRootContext();
    }
    return ctx;
  }

  String _formatError(Object error) {
    if (error is DesktopPermissionException) {
      return error.message;
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  String _tokenPreview(String? token) {
    if (token == null || token.isEmpty) return '-';
    final end = token.length < 8 ? token.length : 8;
    return token.substring(0, end);
  }

  Future<DeviceInfo?> _ensureLocalDeviceInfo() async {
    if (_localDevice != null) return _localDevice;
    try {
      _localDevice = await _bridge.getLocalDeviceInfo();
      return _localDevice;
    } catch (error) {
      final message = '无法读取本机设备ID：${_formatError(error)}';
      if (_error != message) {
        _error = message;
        notifyListeners();
      }
      return null;
    }
  }

  Future<void> _refreshPermissionState({
    bool requestPrompts = false,
  }) async {
    if (!Platform.isMacOS) return;
    final permission = requestPrompts
        ? await _service.requestPermissionPrompts()
        : await _service.getPermissionState();
    _state = AndroidHostState(
      state: _state.state,
      hasPermission: permission.screenRecordingGranted,
      isRunning: _state.isRunning,
      accessibilityEnabled: permission.accessibilityGranted,
      overlayEnabled: _state.overlayEnabled,
      notificationsEnabled: _state.notificationsEnabled,
      batteryOptimizationIgnored: _state.batteryOptimizationIgnored,
      manufacturer: _state.manufacturer,
      message: _state.message,
    );
    notifyListeners();
  }
}
