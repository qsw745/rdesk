import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rdesk/src/providers/auth_provider.dart';
import 'package:rdesk/src/services/rdesk_bridge_service.dart';

import 'support/official_server_http.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('退出账号后旧设备响应不会恢复登录或设备列表', () async {
    const channel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final a = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await a.close(force: true);
    });
    Completer<void>? barrier;
    final pending = Completer<void>();
    a.listen((r) async {
      if (r.uri.path == '/api/account/devices' && barrier != null) {
        pending.complete();
        await barrier!.future;
      }
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode({
        'devices': [
          {'device_id': 'remote-a', 'hostname': 'A 电脑', 'platform': 'windows'}
        ]
      }));
      await r.response.close();
    });
    SharedPreferences.setMockInitialValues({
      'rdesk.account_token': 'session',
      'rdesk.account_user_id': 'user',
      'rdesk.account_username': 'owner',
      'rdesk.account_display_name': 'owner',
    });
    final auth = AuthProvider();
    addTearDown(auth.dispose);
    await HttpOverrides.runWithHttpOverrides(() async {
      await auth.initialize();
      expect(auth.devices.single.deviceId, 'remote-a');
      barrier = Completer<void>();
      final oldRequest = auth.refreshDevices();
      await pending.future;
      await auth.logout();
      expect(auth.devices, isEmpty);
      expect(auth.isLoggedIn, isFalse);
      barrier!.complete();
      await oldRequest;
      expect(auth.devices, isEmpty);
    }, OfficialServerHttp(a.port));
  });

  test('续登失败后清除已失效会话并回到未登录状态', () async {
    const secureStorageChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (_) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, null);
    });

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    final requestPaths = <String>[];
    final requests = server.listen((request) async {
      requestPaths.add(request.uri.path);
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(<String, String>{
        'message': '登录状态已失效',
      }));
      await request.response.close();
    });
    addTearDown(requests.cancel);

    SharedPreferences.setMockInitialValues(<String, Object>{
      'rdesk.account_token': 'stale-token',
      'rdesk.account_user_id': 'user-1',
      'rdesk.account_username': 'qsw',
      'rdesk.account_display_name': 'qsw',
    });

    final auth = AuthProvider();
    addTearDown(auth.dispose);

    await HttpOverrides.runWithHttpOverrides(
      auth.initialize,
      OfficialServerHttp(server.port),
    );

    expect(
      auth.session,
      isNull,
      reason: 'error=${auth.error}; requests=$requestPaths',
    );
    expect(auth.isLoggedIn, isFalse);
    expect(
      await RdeskBridgeService.instance.getSavedAccountSession(),
      isNull,
    );
  });

  test('生物识别已开启时清除失效会话不会恢复旧令牌', () async {
    const secureStorageChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (_) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, null);
    });

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = server.listen((request) async {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(<String, String>{
        'message': '登录状态已失效',
      }));
      await request.response.close();
    });
    addTearDown(requests.cancel);

    SharedPreferences.setMockInitialValues(<String, Object>{
      'rdesk.account_token': 'stale-token',
      'rdesk.account_user_id': 'user-1',
      'rdesk.account_username': 'qsw',
      'rdesk.account_display_name': 'qsw',
      'rdesk.biometric.enabled': true,
      'rdesk.biometric.session.fallback': jsonEncode(<String, String>{
        'token': 'stale-token',
        'user_id': 'user-1',
        'username': 'qsw',
        'display_name': 'qsw',
      }),
    });

    final auth = AuthProvider();
    addTearDown(auth.dispose);

    await HttpOverrides.runWithHttpOverrides(
      auth.initialize,
      OfficialServerHttp(server.port),
    );

    expect(auth.session, isNull);
    expect(auth.canUseBiometricLogin, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('rdesk.biometric.session.fallback'), isNull);
  });
}
