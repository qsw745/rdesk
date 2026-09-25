import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rdesk/src/providers/desktop_host_provider.dart';
import 'package:rdesk/src/providers/session_provider.dart';
import 'package:rdesk/src/models/session.dart';
import 'package:rdesk/src/services/rdesk_bridge_service.dart';

Future<void> eventually(bool Function() check) async {
  final deadline = DateTime.now().add(const Duration(seconds: 4));
  while (!check() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(check(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.qsw.rdesk/desktop_host');
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late HttpServer relay;
  late DesktopHostProvider host;
  var captures = 0;
  var uploads = 0;
  var registrations = 0;
  var relayViewers = 0;
  var leaseMs = 0;
  var epoch = 0;
  var permissionDenied = false;
  Completer<void>? demandDelay;
  Completer<void>? uploadDelay;
  Completer<Map<String, Object>>? frameDelay;

  Future<({int status, String body})> request(String path,
      {Map<String, Object>? body, String? token}) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('http://${host.lanRelayEndpoint}$path').replace(
          queryParameters: token == null ? null : {'session_token': token});
      final req = await client.openUrl(body == null ? 'GET' : 'POST', uri);
      if (body != null) req.write(jsonEncode(body));
      final response = await req.close();
      final bytes = await response
          .fold<List<int>>([], (all, chunk) => all..addAll(chunk));
      return (
        status: response.statusCode,
        body: utf8.decode(bytes, allowMalformed: true)
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<String> authenticate() async {
    final response = await request('/session/trust', body: {
      'deviceId': '222333444',
      'hostname': 'test viewer',
      'peerOs': 'ios',
      'password': 'test-password',
    });
    expect(response.status, 200);
    return (jsonDecode(response.body) as Map)['session_token'] as String;
  }

  setUp(() async {
    HttpOverrides.global = null;
    captures = uploads = registrations = relayViewers = leaseMs = epoch = 0;
    demandDelay = null;
    uploadDelay = null;
    frameDelay = null;
    permissionDenied = false;
    relay = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(relay.forEach((req) async {
      await req.drain<void>();
      req.response.headers.contentType = ContentType.json;
      switch (req.uri.path) {
        case '/api/preview/register':
          registrations++;
          req.response.write(jsonEncode({'host_token': 'test-host'}));
        case '/api/preview/host/viewers':
          final data = {
            'capture_epoch': epoch,
            'viewers': relayViewers,
            'expires_in_ms': leaseMs
          };
          if (demandDelay != null) await demandDelay!.future;
          req.response.write(jsonEncode(data));
        case '/api/preview/host/frame':
          uploads++;
          if (uploadDelay != null) await uploadDelay!.future;
          req.response.write('{}');
        case '/api/preview/host/control/poll':
          req.response.statusCode = 204;
        default:
          req.response.write('{}');
      }
      try {
        await req.response.close();
      } catch (_) {}
    }));
    SharedPreferences.setMockInitialValues({
      'rdesk.device_id': '111222333',
      'rdesk.temp_password': 'test-password',
      'rdesk.signaling_server': 'http://127.0.0.1:${relay.port}',
    });
    RdeskBridgeService.instance.closeHostClient();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(secure, (_) async => null);
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getPermissionState') {
        return {
          'screenRecordingGranted': !permissionDenied,
          'accessibilityGranted': true
        };
      }
      if (call.method == 'captureScreen') {
        captures++;
        if (permissionDenied) {
          throw PlatformException(code: 'PERMISSION_DENIED');
        }
        if (frameDelay != null) return frameDelay!.future;
        return {
          'bytes': Uint8List.fromList([1, 2, 3]),
          'width': 3,
          'height': 1
        };
      }
      if (call.method == 'captureDiagnostics') return {'requests': captures};
      if (call.method == 'listDisplays') return <Map>[];
      return null;
    });
    host = DesktopHostProvider(lanPort: 0);
    await host.initialize();
    await host.startHosting();
  });

  tearDown(() async {
    demandDelay?.complete();
    demandDelay = null;
    uploadDelay?.complete();
    uploadDelay = null;
    await host.stopHosting();
    host.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await relay.close(force: true);
    RdeskBridgeService.instance.closeHostClient();
    RdeskBridgeService.instance.closePersistentClients();
  });

  test('待命、鉴权失败、仅鉴权及非画面请求均不采集，直连观看后按需释放', () async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(registrations, greaterThan(0));
    expect(host.error, isNull);
    expect(captures, 0);
    expect((await request('/frame.jpg', token: 'invalid')).status, 401);
    expect(
        (await request('/session/trust', body: {
          'deviceId': '222333444',
          'hostname': 'test',
          'peerOs': 'ios',
          'password': 'wrong',
        }))
            .status,
        401);
    final token = await authenticate();
    await request('/displays', token: token);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(captures, 0);
    await request('/frame.jpg', token: token);
    await eventually(() => host.previewFrame != null);
    expect((await request('/frame.jpg', token: token)).status, 200);
    expect(uploads, 0, reason: '直连画面不得顺便上传中继');
    await request('/session/close', token: token, body: {});
    expect(host.captureRunning, isFalse);
    expect(host.previewFrame, isNull);
    final stopped = captures;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(captures, stopped);
    expect((await request('/frame.jpg', token: token)).status, 401);
  });

  test('中继观看和迟到快照、手动停止及超过恢复周期均尊重停止意图', () async {
    relayViewers = 1;
    leaseMs = 10000;
    epoch = 1;
    await eventually(() => uploads > 0);
    relayViewers = 0;
    leaseMs = 0;
    await eventually(() => !host.captureRunning);
    expect(host.previewFrame, isNull);
    relayViewers = 1;
    leaseMs = 10000;
    epoch = 2;
    demandDelay = Completer<void>();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await host.stopHosting();
    demandDelay!.complete();
    demandDelay = null;
    await host.retryAfterPermissionGrant();
    await host.refresh();
    final stopped = captures;
    final stoppedUploads = uploads;
    await Future<void>.delayed(const Duration(seconds: 9));
    expect(host.hostingEnabled, isFalse);
    expect(host.captureRunning, isFalse);
    expect(captures, stopped);
    expect(uploads, stoppedUploads);
  }, timeout: const Timeout(Duration(seconds: 25)));

  test('直连异常断线在十秒租约内释放，并可再次连接', () async {
    final token = await authenticate();
    await request('/frame.jpg', token: token);
    await eventually(() => host.previewFrame != null);
    await Future<void>.delayed(const Duration(milliseconds: 10400));
    expect(host.captureRunning, isFalse);
    expect(host.previewFrame, isNull);
    await request('/frame.jpg', token: token);
    await eventually(() => host.previewFrame != null);
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('最后观看者释放后丢弃在途画面，多观看者及快速重连仍正常', () async {
    final first = await authenticate();
    final second = await authenticate();
    await request('/frame.jpg', token: first);
    await request('/frame.jpg', token: second);
    await eventually(() => captures > 0);
    await request('/session/close', token: first, body: {});
    expect(host.captureRunning, isTrue);
    frameDelay = Completer<Map<String, Object>>();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await request('/session/close', token: second, body: {});
    frameDelay!.complete({
      'bytes': Uint8List.fromList([9]),
      'width': 1,
      'height': 1
    });
    frameDelay = null;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(host.previewFrame, isNull);
    for (var i = 0; i < 3; i++) {
      final token = await authenticate();
      await request('/frame.jpg', token: token);
      await eventually(() => host.previewFrame != null);
      await request('/session/close', token: token, body: {});
      expect(host.captureRunning, isFalse);
    }
  });

  test('权限恢复只在仍有观看需求时重试', () async {
    permissionDenied = true;
    final token = await authenticate();
    await request('/frame.jpg', token: token);
    await eventually(() => captures > 0);
    expect(host.previewFrame, isNull);
    permissionDenied = false;
    await host.retryAfterPermissionGrant();
    await eventually(() => host.previewFrame != null);
    await request('/session/close', token: token, body: {});
    final stopped = captures;
    await host.retryAfterPermissionGrant();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(captures, stopped);
  });
  test('画面订阅只在远程桌面可见时运行，文件状态保留认证', () async {
    final bridge = RdeskBridgeService.instance;
    final id = await bridge.connectDirectIp(host.lanRelayEndpoint!,
        password: 'test-password');
    final viewer = SessionProvider();
    viewer.setSession(SessionInfo(
        sessionId: id,
        peerId: '111222333',
        peerHostname: 'test',
        peerOs: 'macos',
        state: SessionState.active,
        connectedAt: DateTime.now()));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(captures, 0);
    viewer.resumeScreenViewing(id);
    await eventually(() => host.captureRunning);
    await viewer.pauseScreenViewing(id);
    expect(host.captureRunning, isFalse);
    expect(viewer.currentSession?.sessionId, id);
    expect(await bridge.fetchRemoteDisplays(id), isEmpty);
    final stopped = captures;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(captures, stopped);
    viewer.resumeScreenViewing(id);
    await eventually(() => host.captureRunning);
    await bridge.disconnect(id);
    await viewer.pauseScreenViewing(id);
    viewer.clearSession();
    viewer.dispose();
    expect(host.captureRunning, isFalse);
  });
  test('中继在途上传在停止时中断，迟到响应不能留下画面', () async {
    uploadDelay = Completer<void>();
    relayViewers = 1; leaseMs = 10000; epoch = 1;
    await eventually(() => uploads > 0);
    await host.stopHosting();
    expect(host.captureRunning, isFalse);
    final stopped = captures;
    uploadDelay!.complete(); uploadDelay = null;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(captures, stopped);
    expect(host.previewFrame, isNull);
  });

  test('中继失联不能延长已经确认的观看租约', () async {
    relayViewers = 1; leaseMs = 1500; epoch = 1;
    await eventually(() => uploads > 0);
    demandDelay = Completer<void>();
    await Future<void>.delayed(const Duration(milliseconds: 2800));
    expect(host.captureRunning, isFalse);
    expect(host.previewFrame, isNull);
  });

}
