import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../models/device.dart';
import '../services/rdesk_bridge_service.dart';
import '../services/android_host_service.dart'; // Reuse AndroidHostState / AndroidHostFrame
import '../services/desktop_host_service.dart';

/// Host provider for desktop platforms (macOS, Windows, Linux).
///
/// Mirrors [AndroidHostProvider] but uses [DesktopHostService] for
/// screen capture and input simulation instead of Android MethodChannel.
class DesktopHostProvider extends ChangeNotifier {
  final _bridge = RdeskBridgeService.instance;
  final _service = DesktopHostService.instance;

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
  HttpServer? _lanRelayServer;
  String? _lanRelayEndpoint;
  DeviceInfo? _localDevice;
  String? _relayHostToken;
  bool _relayCommandBusy = false;
  bool _relayUploadBusy = false;
  int? _lastUploadedFrameTimestampMs;

  AndroidHostState get state => _state;
  AndroidHostFrame? get previewFrame => _previewFrame;
  String? get lanRelayEndpoint => _lanRelayEndpoint;
  bool get busy => _busy;
  String? get error => _error;
  bool get canDisconnectViewers =>
      _state.isRunning &&
      _localDevice != null &&
      (_relayHostToken?.isNotEmpty ?? false);

  Future<void> initialize({bool enabled = true}) async {
    if (!enabled) return;
    _localDevice = await _bridge.getLocalDeviceInfo();
    await _run(() async {
      _state = await _service.getState();
    }, clearError: false);
  }

  Future<void> startHosting() async {
    await _run(() async {
      _state = await _service.startHosting();
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
        _relayHostToken = null;
        _lastUploadedFrameTimestampMs = null;
        if (_localDevice != null) {
          try {
            await _bridge.unregisterPreviewHost(_localDevice!.deviceId);
          } catch (_) {}
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

  @override
  void dispose() {
    _previewTimer?.cancel();
    _registrationTimer?.cancel();
    _relayCommandTimer?.cancel();
    unawaited(_closeLanRelay(notify: false));
    super.dispose();
  }

  Future<bool> disconnectCurrentViewer() async {
    final device = _localDevice;
    final hostToken = _relayHostToken;
    if (!_state.isRunning || device == null) {
      return false;
    }

    await _run(() async {
      if (hostToken != null && hostToken.isNotEmpty) {
        try {
          await _bridge.disconnectHostedViewers(
            deviceId: device.deviceId,
            hostToken: hostToken,
          );
        } catch (_) {
          // Server-side cleanup is best effort; local reset below is what
          // reliably severs the active viewer session.
        }
      }

      await _closeLanRelay();
      _relayHostToken = null;
      _lastUploadedFrameTimestampMs = null;

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

  void _ensurePreviewPolling() {
    _previewTimer?.cancel();
    if (!_state.isRunning) return;
    unawaited(_pollPreviewFrame());
    _previewTimer = Timer.periodic(
      const Duration(milliseconds: 300), // ~3.3 fps for desktop
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
        if (changed) notifyListeners();
        await _uploadRelayFrame(frame);
      }
    } catch (_) {}
  }

  void _ensureRelayCommandPolling() {
    _relayCommandTimer?.cancel();
    if (!_state.isRunning || _relayHostToken == null || _localDevice == null) {
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
    if (_lanRelayServer != null) return;

    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _lanRelayServer = server;
    final localIp = await _resolveLocalIpv4();
    _lanRelayEndpoint = localIp != null
        ? '$localIp:${server.port}'
        : '127.0.0.1:${server.port}';
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
          response.write(jsonEncode(<String, Object?>{
            'state': _state.state,
            'running': _state.isRunning,
            'hasPermission': _state.hasPermission,
            'hasFrame': _previewFrame != null,
            'endpoint': _lanRelayEndpoint,
            'platform': Platform.operatingSystem,
          }));
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
    _lastUploadedFrameTimestampMs = null;
    if (notify) notifyListeners();
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
  }

  // ---------- signaling server registration ----------

  Future<void> _registerPreviewHost() async {
    final device = _localDevice;
    final endpoint = _lanRelayEndpoint;
    if (device == null || endpoint == null || !_state.isRunning) return;

    if (_relayHostToken == null) {
      try {
        await _bridge.unregisterPreviewHost(device.deviceId);
      } catch (_) {}
    }

    final password = await _bridge.getActiveAccessPassword();
    final settings = await _bridge.loadSettings();
    final trustedViewerIds = await _bridge.listTrustedIncomingViewerIds();

    final hostToken = await _bridge.registerPreviewHost(
      deviceId: device.deviceId,
      endpoint: endpoint,
      platform: device.os,
      hostname: device.hostname,
      password: password,
      autoAccept: settings.autoAccept,
      trustedViewerIds: trustedViewerIds,
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
    } finally {
      _relayUploadBusy = false;
    }
  }

  Future<void> _pollRelayCommand() async {
    if (_relayCommandBusy) return;
    final device = _localDevice;
    final hostToken = _relayHostToken;
    if (device == null || hostToken == null || hostToken.isEmpty) return;

    _relayCommandBusy = true;
    try {
      final command = await _bridge.pollHostedCommand(
        deviceId: device.deviceId,
        hostToken: hostToken,
      );
      if (command == null || command.commandId.isEmpty) return;

      var ok = false;
      String? text;
      switch (command.kind) {
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
        case 'tap':
          final x = (command.payload['x'] as num?)?.toDouble();
          final y = (command.payload['y'] as num?)?.toDouble();
          if (x != null && y != null) {
            ok =
                await _service.performRemoteTap(normalizedX: x, normalizedY: y);
          }
        case 'action':
          final action = command.payload['action'] as String?;
          if (action != null && action.isNotEmpty) {
            ok = await _service.performRemoteAction(action);
          }
        case 'long_press':
          final x = (command.payload['x'] as num?)?.toDouble();
          final y = (command.payload['y'] as num?)?.toDouble();
          if (x != null && y != null) {
            ok = await _service.performRemoteLongPress(
                normalizedX: x, normalizedY: y);
          }
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
        case 'text':
          final input = command.payload['text'] as String?;
          if (input != null) {
            ok = await _service.performRemoteTextInput(input);
          }
        case 'clipboard_set':
          final input = command.payload['text'] as String?;
          if (input != null) {
            ok = await _service.setClipboardText(input);
          }
        case 'clipboard_get':
          text = await _service.getClipboardText();
          ok = true;
      }

      await _bridge.submitHostedCommandResult(
        deviceId: device.deviceId,
        hostToken: hostToken,
        commandId: command.commandId,
        ok: ok,
        text: text,
      );
    } catch (_) {
    } finally {
      _relayCommandBusy = false;
    }
  }
}
