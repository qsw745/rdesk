import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:rdesk/src/providers/auth_provider.dart';
import 'package:rdesk/src/services/rdesk_bridge_service.dart';

import 'support/official_server_http.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();
  final bridge = RdeskBridgeService.instance;
  const account = {
    'rdesk.account_token': 'old-token',
    'rdesk.account_user_id': 'owner-id',
    'rdesk.account_username': 'owner',
  };
  final biometric = jsonEncode({
    'token': 'biometric-token',
    'user_id': 'owner-id',
    'username': 'owner',
  });
  late HttpServer server;
  late OfficialServerHttp http;
  final requests = <Uri>[];
  final passwords = <String>[];
  final tokens = <String>[];
  final frames = <List<int>>[];
  final secureValues = <String, String>{};
  bool failStorage = false;
  bool redirectDevices = false;
  Completer<void>? storageGate;
  int deletes = 0;
  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    secureValues.clear();
    failStorage = false;
    redirectDevices = false;
    storageGate = null;
    deletes = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async {
      if (failStorage) throw PlatformException(code: 'storage_unavailable');
      await storageGate?.future;
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final key = args['key'] as String?;
      switch (call.method) {
        case 'read':
          return secureValues[key];
        case 'write':
          secureValues[key!] = args['value'] as String;
          return null;
        case 'delete':
          deletes++;
          secureValues.remove(key);
          return null;
        case 'containsKey':
          return secureValues.containsKey(key);
        case 'readAll':
          return Map<String, String>.from(secureValues);
        default:
          throw UnsupportedError(call.method);
      }
    });
    bridge.closeHostClient();
    bridge.closePersistentClients();
    requests.clear();
    passwords.clear();
    tokens.clear();
    frames.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final bytes =
          await request.fold<List<int>>([], (all, part) => all..addAll(part));
      final body = utf8.decode(bytes, allowMalformed: true);
      final token = request.headers.value(HttpHeaders.authorizationHeader);
      if (token != null) tokens.add(token);
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/api/preview/host/frame') {
        frames.add(bytes);
        request.response.write('{}');
      } else if (redirectDevices &&
          request.uri.path == '/api/account/devices') {
        request.response.statusCode = 302;
        request.response.headers.set(HttpHeaders.locationHeader,
            'http://127.0.0.1:${server.port}/redirected');
      } else if (request.uri.path == '/api/account/login') {
        passwords.add((jsonDecode(body) as Map)['password'] as String);
        request.response.write(jsonEncode({
          'token': 'new-token',
          'user_id': 'owner-id',
          'username': 'owner',
        }));
      } else {
        request.response.write('{"devices":[]}');
      }
      await request.response.close();
    });
    http = OfficialServerHttp(server.port, onRequest: requests.add);
  });
  tearDown(() async {
    bridge.closeHostClient();
    bridge.closePersistentClients();
    await server.close(force: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  test('任意旧自定义配置都不能更改账号请求的官方 HTTPS 目标', () async {
    for (final address in [
      'https://untrusted.invalid',
      'http://untrusted.invalid',
      'untrusted.invalid:21116',
      'https://qisw.top.evil.invalid',
    ]) {
      SharedPreferences.setMockInitialValues({
        'rdesk.signaling_server': address,
        'rdesk.relay_server': address,
      });
      await HttpOverrides.runWithHttpOverrides(() async {
        await bridge.loginAccount(username: 'owner', password: 'manual-login');
      }, http);
    }
    expect(passwords, hasLength(4));
    expect(requests.map((uri) => uri.origin).toSet(), {'https://qisw.top'});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('rdesk.signaling_server'), isNull);
    expect(prefs.getString('rdesk.relay_server'), isNull);
  });

  test('自定义来源升级时清除令牌、自动续登、生物识别和可信设备', () async {
    SharedPreferences.setMockInitialValues({
      ...account,
      'rdesk.signaling_server': 'https://untrusted.invalid',
      'rdesk.trusted_peers': '[{"device_id":"old-peer"}]',
      'rdesk.trusted_incoming_viewers': '[{"device_id":"old-viewer"}]',
      'rdesk.biometric.enabled': true,
      'rdesk.biometric.session.fallback': biometric,
      'rdesk.theme': 'dark',
    });
    secureValues.addAll({
      'rdesk.account.credentials': '{"u":"owner","p":"old-password"}',
      'rdesk.biometric.session': biometric,
      'rdesk.permanent_password': 'local-access-password',
    });
    final auth = AuthProvider();
    addTearDown(auth.dispose);
    await HttpOverrides.runWithHttpOverrides(auth.initialize, http);
    expect(auth.isLoggedIn, isFalse);
    expect(auth.canUseBiometricLogin, isFalse);
    expect(requests, isEmpty);
    expect(await storage.read(key: 'rdesk.account.credentials'), isNull);
    expect(await storage.read(key: 'rdesk.biometric.session'), isNull);
    expect(await bridge.getSavedAccountSession(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('rdesk.biometric.session.fallback'), isNull);
    expect(prefs.getString('rdesk.trusted_peers'), isNull);
    expect(prefs.getString('rdesk.trusted_incoming_viewers'), isNull);
    expect(prefs.getString('rdesk.theme'), 'dark');
    expect(await storage.read(key: 'rdesk.permanent_password'),
        'local-access-password');
  });

  test('历史官方配置可保留会话，并在发请求前绑定来源', () async {
    SharedPreferences.setMockInitialValues({
      ...account,
      'rdesk.signaling_server': 'http://qisw.top:21116',
    });
    final auth = AuthProvider();
    addTearDown(auth.dispose);
    await HttpOverrides.runWithHttpOverrides(auth.initialize, http);
    expect(auth.isLoggedIn, isTrue);
    expect(tokens, contains('Bearer old-token'));
    expect(requests.map((uri) => uri.origin).toSet(), {'https://qisw.top'});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('rdesk.account_server'), 'https://qisw.top');
  });

  test('官方旧凭据可续登且安全存储绑定来源', () async {
    secureValues.addAll({
      'rdesk.account.credentials': '{"u":"owner","p":"official-password"}',
    });
    final auth = AuthProvider();
    addTearDown(auth.dispose);
    await HttpOverrides.runWithHttpOverrides(auth.initialize, http);
    expect(auth.isLoggedIn, isTrue);
    expect(passwords, ['official-password']);
    final credentials =
        jsonDecode((await storage.read(key: 'rdesk.account.credentials'))!)
            as Map;
    expect(credentials['server'], 'https://qisw.top');
  });

  test('自定义来源的可信设备密码含孤儿键均不再用于连接', () async {
    SharedPreferences.setMockInitialValues({
      'rdesk.signaling_server': 'https://untrusted.invalid',
    });
    secureValues.addAll({
      'rdesk.trusted_peers.pw.123456789': 'foreign-peer-password',
      'rdesk.trusted_peers.pw.orphan': 'orphan-password',
      'unrelated.secret': 'keep-me',
    });
    expect(await bridge.getTrustedPeerPassword('123456789'), isNull);
    expect(secureValues.containsKey('rdesk.trusted_peers.pw.orphan'), isFalse);
    expect(secureValues['unrelated.secret'], 'keep-me');
  });

  test('历史官方可信设备密码绑定来源后仍可使用', () async {
    secureValues['rdesk.trusted_peers.pw.123456789'] = 'official-peer-password';
    expect(await bridge.getTrustedPeerPassword('123456789'),
        'official-peer-password');
    final payload =
        jsonDecode(secureValues['rdesk.trusted_peers.pw.123456789']!) as Map;
    expect(payload['server'], 'https://qisw.top');
    expect(payload['password'], 'official-peer-password');
  });

  test('已完成迁移时不接受无来源或错误来源的可信设备密码', () async {
    SharedPreferences.setMockInitialValues({
      'rdesk.server_policy_origin': 'https://qisw.top',
    });
    secureValues.addAll({
      'rdesk.trusted_peers.pw.raw': 'unscoped-password',
      'rdesk.trusted_peers.pw.foreign': jsonEncode({
        'server': 'https://untrusted.invalid',
        'password': 'foreign-password',
      }),
    });
    expect(await bridge.getTrustedPeerPassword('raw'), isNull);
    expect(await bridge.getTrustedPeerPassword('foreign'), isNull);
    await bridge.rememberTrustedPeer(
        deviceId: '123456789',
        password: 'new-password',
        hostname: 'my device',
        peerOs: 'windows');
    expect(await bridge.getTrustedPeerPassword('123456789'), 'new-password');
  });

  test('其他官方来源遗留凭据不向新来源续登', () async {
    SharedPreferences.setMockInitialValues({
      ...account,
      'rdesk.server_policy_origin': 'https://retired.invalid',
      'rdesk.account_server': 'https://retired.invalid',
    });
    secureValues.addAll({
      'rdesk.account.credentials': jsonEncode({
        'u': 'owner',
        'p': 'retired-password',
        'server': 'https://retired.invalid',
      }),
    });
    final auth = AuthProvider();
    addTearDown(auth.dispose);
    await HttpOverrides.runWithHttpOverrides(auth.initialize, http);
    expect(auth.isLoggedIn, isFalse);
    expect(requests, isEmpty);
    expect(await storage.read(key: 'rdesk.account.credentials'), isNull);
  });

  test('完成迁移后仍拒绝来源不符的续登凭据', () async {
    SharedPreferences.setMockInitialValues({
      'rdesk.server_policy_origin': 'https://qisw.top',
    });
    secureValues.addAll({
      'rdesk.account.credentials': jsonEncode({
        'u': 'owner',
        'p': 'foreign-password',
        'server': 'https://untrusted.invalid',
      }),
    });
    final auth = AuthProvider();
    addTearDown(auth.dispose);
    await HttpOverrides.runWithHttpOverrides(auth.initialize, http);
    expect(auth.isLoggedIn, isFalse);
    expect(passwords, isEmpty);
  });

  test('被控注册和 JPEG 上传均不采用旧自定义地址', () async {
    SharedPreferences.setMockInitialValues({
      'rdesk.signaling_server': 'https://untrusted.invalid',
    });
    await HttpOverrides.runWithHttpOverrides(() async {
      await bridge.registerPreviewHost(
        deviceId: '123456789',
        password: 'host-password',
        hostname: 'test',
        platform: 'windows',
        endpoint: '127.0.0.1:21118',
        autoAccept: false,
        trustedViewerIds: [],
      );
      await bridge.uploadRelayPreviewFrame(
          deviceId: '123456789',
          hostToken: 'test-host',
          bytes: Uint8List.fromList([255, 216, 255, 217]),
          width: 1,
          height: 1,
          timestampMs: 1);
    }, http);
    expect(requests, isNotEmpty);
    expect(requests.map((uri) => uri.origin).toSet(), {'https://qisw.top'});
    expect(frames, [
      [255, 216, 255, 217]
    ]);
  });

  test('并发账号与托管启动均等待同一迁移完成', () async {
    SharedPreferences.setMockInitialValues({
      'rdesk.signaling_server': 'https://untrusted.invalid',
    });
    storageGate = Completer<void>();
    await HttpOverrides.runWithHttpOverrides(() async {
      final pending = Future.wait([
        bridge.getApiBaseUri(),
        bridge.getSavedAccountSession(),
        bridge.loginAccount(username: 'owner', password: 'manual-login'),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(requests, isEmpty);
      storageGate!.complete();
      await pending;
    }, http);
    expect(deletes, 2);
    expect(passwords, ['manual-login']);
  });

  test('账号请求拒绝跟随重定向到明文或其他来源', () async {
    SharedPreferences.setMockInitialValues({...account});
    redirectDevices = true;
    await HttpOverrides.runWithHttpOverrides(() async {
      await expectLater(bridge.listAccountDevices(), throwsException);
    }, http);
    expect(tokens.where((token) => token == 'Bearer old-token'), hasLength(2));
  });

  test('初始化遇到安全存储故障时保持退出并提供可恢复错误', () async {
    SharedPreferences.setMockInitialValues({
      ...account,
      'rdesk.signaling_server': 'https://untrusted.invalid',
    });
    failStorage = true;
    final auth = AuthProvider();
    addTearDown(auth.dispose);
    await HttpOverrides.runWithHttpOverrides(auth.initialize, http);
    expect(auth.initialized, isTrue);
    expect(auth.isLoggedIn, isFalse);
    expect(auth.error, isNotEmpty);
    expect(requests, isEmpty);
  });

  test('安全存储清理失败时不能先改来源或发送请求', () async {
    SharedPreferences.setMockInitialValues({
      ...account,
      'rdesk.signaling_server': 'https://untrusted.invalid',
    });
    failStorage = true;
    await HttpOverrides.runWithHttpOverrides(() async {
      await expectLater(
        bridge.loginAccount(username: 'owner', password: 'manual-login'),
        throwsA(isA<PlatformException>()),
      );
    }, http);
    expect(requests, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(
        prefs.getString('rdesk.signaling_server'), 'https://untrusted.invalid');
    expect(prefs.getString('rdesk.server_policy_origin'), isNull);
  });

  for (final throwsOnWrite in [false, true]) {
    test('完成标记写入${throwsOnWrite ? '抛错' : '返回失败'}后必须重新迁移', () async {
      final disk = _UnreliablePreferences(throwsOnWrite: throwsOnWrite);
      SharedPreferencesStorePlatform.instance = disk;
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      await expectLater(bridge.getApiBaseUri(), throwsA(anything));
      expect(
          (await disk.getAll())['flutter.rdesk.server_policy_origin'], isNull);
      disk.failMarker = false;
      await bridge.getApiBaseUri();
      expect((await disk.getAll())['flutter.rdesk.server_policy_origin'],
          'https://qisw.top');
    });
  }

  test('完成标记尚未落盘时并发请求也必须等待', () async {
    final disk = _UnreliablePreferences(throwsOnWrite: false)
      ..failMarker = false;
    disk.markerGate = Completer<void>();
    SharedPreferencesStorePlatform.instance = disk;
    await (await SharedPreferences.getInstance()).reload();
    await HttpOverrides.runWithHttpOverrides(() async {
      final migration = bridge.getApiBaseUri();
      await disk.markerStarted.future;
      final login =
          bridge.loginAccount(username: 'owner', password: 'manual-login');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final prematureRequests = requests.length;
      disk.markerGate!.complete();
      await Future.wait([migration, login]);
      expect(prematureRequests, 0);
    }, http);
  });
}

class _UnreliablePreferences extends InMemorySharedPreferencesStore {
  final bool throwsOnWrite;
  bool failMarker = true;
  Completer<void>? markerGate;
  final markerStarted = Completer<void>();
  _UnreliablePreferences({required this.throwsOnWrite}) : super.empty();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.rdesk.server_policy_origin') {
      if (!markerStarted.isCompleted) markerStarted.complete();
      await markerGate?.future;
      if (failMarker) {
        if (throwsOnWrite) throw StateError('disk unavailable');
        return false;
      }
    }
    return super.setValue(valueType, key, value);
  }
}
