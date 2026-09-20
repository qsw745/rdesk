import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'wake_api_test.dart' show RealHttp;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/services/wake_api.dart';
import 'package:rdesk/src/services/windows_wake_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('专用上线心跳按账号隔离，停止后不继续发送', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    HttpOverrides.global = RealHttp();
    final endpoint = Uri.parse('http://127.0.0.1:${server.port}');
    final beats = <String>[];
    server.listen((request) async {
      beats.add(request.headers.value(HttpHeaders.authorizationHeader)!);
      expect(request.uri.path, '/api/wake/targets/pc/heartbeat');
      request.response.write('{}');
      await request.response.close();
    });
    final key =
        'rdesk.wake.windows.${sha256.convert(utf8.encode('$endpoint|user'))}';
    FlutterSecureStorage.setMockInitialValues({
      key: jsonEncode({'id': 'pc', 'token': 'device-token'})
    });
    final api = WakeApi(
        baseUri: () async => endpoint,
        accountToken: () async => 'account-token');
    final service = WindowsWakeService(
        api: api,
        storage: const FlutterSecureStorage(),
        run: (_, __) async => ProcessResult(0, 0, '', ''));
    try {
      await service.resume('other');
      expect(beats, isEmpty);
      await service.resume('user');
      expect(beats, ['Bearer device-token']);
      expect(service.active, true);
      await service.stop();
      expect(service.active, false);
      await service.forget('user');
      await service.resume('user');
      expect(beats.length, 1);
    } finally {
      await service.stop();
      api.close();
      await server.close(force: true);
      HttpOverrides.global = null;
    }
  });
  test('检测仅按真实值判断，未知关机唤醒不能显示通过', () async {
    final api = WakeApi(
        baseUri: () async => Uri.parse('https://example.test'),
        accountToken: () async => 'a');
    addTearDown(api.close);
    final service = WindowsWakeService(
        api: api,
        storage: const FlutterSecureStorage(),
        run: (_, args) async => ProcessResult(
            1,
            0,
            '{"magicPacket":"Enabled","wakeArmed":false,"shutdownWake":null}',
            ''));
    final result = await service.inspect('02:11:22:33:44:55');
    expect(result.magicPacket, WakeCheckState.enabled);
    expect(result.wakeArmed, WakeCheckState.disabled);
    expect(result.shutdownWake, WakeCheckState.unknown);
    expect(result.allEnabled, isFalse);
  });
  test('网卡检测失败不能当成全部开启', () async {
    final api = WakeApi(
        baseUri: () async => Uri.parse('https://example.test'),
        accountToken: () async => 'a');
    addTearDown(api.close);
    final service = WindowsWakeService(
        api: api,
        storage: const FlutterSecureStorage(),
        run: (_, __) async => ProcessResult(1, 1, '', 'Access denied'));
    await expectLater(
        service.inspect('02:11:22:33:44:55'), throwsA(isA<WakeApiException>()));
  });
}
