import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../models/device.dart';
import '../services/rdesk_bridge_service.dart';
import '../services/android_host_service.dart';

class AndroidHostProvider extends ChangeNotifier {
  final _bridge = RdeskBridgeService.instance;
  final _service = AndroidHostService.instance;

  AndroidHostState _state = const AndroidHostState(
    state: 'idle',
    hasPermission: false,
    isRunning: false,
    accessibilityEnabled: false,
  );
  AndroidHostFrame? _previewFrame;
  bool _busy = false;
  String? _error;
  Timer? _previewTimer;
  Timer? _registrationTimer;
  HttpServer? _lanRelayServer;
  String? _lanRelayEndpoint;
  DeviceInfo? _localDevice;
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

  Future<void> initialize({bool enabled = true}) async {
    if (!enabled) {
      return;
    }
    _localDevice = await _bridge.getLocalDeviceInfo();
    await _run(() async {
      _state = await _service.getState();
    }, clearError: false);
  }

  Future<void> requestPermission() async {
    await _run(() async {
      _state = await _service.requestPermission();
    });
  }

  Future<void> startHosting() async {
    await _run(() async {
      _state = await _service.startHosting();
      _ensurePreviewPolling();
      await _ensureLanRelay();
      await _registerPreviewHost();
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
        if (_localDevice != null) {
          try {
            await _bridge.unregisterPreviewHost(_localDevice!.deviceId);
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
      }
    }, clearError: false);
  }

  Future<void> openAccessibilitySettings() =>
      _service.openAccessibilitySettings();

  @override
  void dispose() {
    _previewTimer?.cancel();
    _registrationTimer?.cancel();
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
      const Duration(milliseconds: 1200),
      (_) => unawaited(_pollPreviewFrame()),
    );
  }

  Future<void> _pollPreviewFrame() async {
    try {
      final frame = await _service.getLatestFrame();
      if (frame != null) {
        _previewFrame = frame;
        notifyListeners();
      }
    } catch (_) {
      // Ignore transient preview polling failures while the service is warming up.
    }
  }

  Future<void> _ensureLanRelay() async {
    if (_lanRelayServer != null) {
      return;
    }

    final server = await HttpServer.bind(InternetAddress.anyIPv4, 22330);
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
          response.add(frame.bytes);
          await response.close();
          return;
        }

        if (request.uri.path == '/health') {
          response.headers.contentType = ContentType.json;
          response.write(
            jsonEncode(<String, Object?>{
              'state': _state.state,
              'running': _state.isRunning,
              'hasPermission': _state.hasPermission,
              'hasFrame': _previewFrame != null,
              'endpoint': _lanRelayEndpoint,
            }),
          );
          await response.close();
          return;
        }

        if (request.uri.path == '/session/trust' && request.method == 'POST') {
          final body = await utf8.decoder.bind(request).join();
          final payload = jsonDecode(body) as Map<String, dynamic>;
          final deviceId = payload['deviceId'] as String?;
          final hostname = payload['hostname'] as String?;
          final peerOs = payload['peerOs'] as String?;
          if (deviceId == null || hostname == null || peerOs == null) {
            response.statusCode = HttpStatus.badRequest;
            response.write('missing viewer info');
            await response.close();
            return;
          }

          await _bridge.trustIncomingViewer(
            deviceId: deviceId,
            hostname: hostname,
            peerOs: peerOs,
          );
          await _registerPreviewHost();
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(<String, Object?>{'ok': true}));
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
          try {
            await _service.showRemoteTapIndicator(
              normalizedX: x,
              normalizedY: y,
            );
          } catch (_) {
            // Keep endpoint available even if native indicator fails.
          }

          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(<String, Object?>{'ok': true}));
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
          final ok = await _service.performRemoteAction(action);
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

        response.statusCode = HttpStatus.notFound;
        response.write('not found');
        await response.close();
      }),
    );
  }

  Future<void> _closeLanRelay({bool notify = true}) async {
    await _lanRelayServer?.close(force: true);
    _lanRelayServer = null;
    _lanRelayEndpoint = null;
    if (notify) {
      notifyListeners();
    }
  }

  Future<String?> _resolveLocalIpv4() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback && address.address.contains('.')) {
          return address.address;
        }
      }
    }
    return null;
  }

  Future<void> _registerPreviewHost() async {
    final device = _localDevice;
    final endpoint = _lanRelayEndpoint;
    if (device == null || endpoint == null || !_state.isRunning) {
      return;
    }
    final password = await _bridge.getActiveAccessPassword();
    final settings = await _bridge.loadSettings();
    final trustedViewerIds = await _bridge.listTrustedIncomingViewerIds();

    await _bridge.registerPreviewHost(
      deviceId: device.deviceId,
      endpoint: endpoint,
      platform: device.os,
      hostname: device.hostname,
      password: password,
      autoAccept: settings.autoAccept,
      trustedViewerIds: trustedViewerIds,
    );

    _registrationTimer?.cancel();
    _registrationTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_registerPreviewHost()),
    );
  }
}
