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
  test('识别实际有线网卡并排除无效 MAC', () async {
    final api = WakeApi(
        baseUri: () async => Uri.parse('https://example.test'),
        accountToken: () async => 'a');
    addTearDown(api.close);
    final service = WindowsWakeService(
        api: api,
        storage: const FlutterSecureStorage(),
        run: (exe, args) async {
          expect(exe, 'powershell.exe');
          expect(args, contains('-NonInteractive'));
          return ProcessResult(
              1,
              0,
              '[{"InterfaceGuid":"wired","Name":"以太网","MacAddress":"02-11-22-33-44-55","Status":"Up","NdisPhysicalMedium":14},{"InterfaceGuid":"invalid","Name":"虚拟","MacAddress":"00-00-00-00-00-00","Status":"Up","NdisPhysicalMedium":"Unspecified"}]',
              '');
        });
    final adapters = await service.adapters();
    expect(adapters.length, 1);
    expect(adapters.single.mac, '02:11:22:33:44:55');
    expect(adapters.single.wired, isTrue);
  });
  test('单对象无线适配器不能宣称支持有线唤醒', () async {
    final api = WakeApi(
        baseUri: () async => Uri.parse('https://example.test'),
        accountToken: () async => 'a');
    addTearDown(api.close);
    final service = WindowsWakeService(
        api: api,
        storage: const FlutterSecureStorage(),
        run: (exe, args) async => ProcessResult(
            1,
            0,
            '{"InterfaceGuid":"wifi","Name":"无线网络","MacAddress":"02-11-22-33-44-55","Status":"Up","NdisPhysicalMedium":9}',
            ''));
    expect((await service.adapters()).single.wired, isFalse);
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
  test('物理介质未指定时使用以太网接口类型，不混淆无线接口', () async {
    final api = WakeApi(
        baseUri: () async => Uri.parse('https://example.test'),
        accountToken: () async => 'a');
    addTearDown(api.close);
    final service = WindowsWakeService(
        api: api,
        storage: const FlutterSecureStorage(),
        run: (_, __) async => ProcessResult(
            1,
            0,
            '[{"Name":"Ethernet","MacAddress":"02-11-22-33-44-55","Status":"Up","NdisPhysicalMedium":0,"InterfaceType":6},{"Name":"Wi-Fi","MacAddress":"02-11-22-33-44-56","Status":"Up","NdisPhysicalMedium":0,"InterfaceType":71}]',
            ''));
    final adapters = await service.adapters();
    expect(adapters.first.wired, isTrue);
    expect(adapters.last.wired, isFalse);
  });
}
