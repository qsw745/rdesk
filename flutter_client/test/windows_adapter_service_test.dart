import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/services/wake_api.dart';
import 'package:rdesk/src/services/windows_wake_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.qsw.rdesk/windows_wake');
  late WakeApi api;
  late WindowsWakeService service;
  Map<String, Object> row(String id,
          {int type = 6,
          bool hardware = true,
          bool connected = true,
          String mac = '02-11-22-33-44-55'}) =>
      {
        'id': id,
        'name': '中文以太网 $id',
        'mac': mac,
        'if_type': type,
        'hardware': hardware,
        'connected': connected,
      };
  void respond(List<Map<String, Object>> rows) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'listAdapters');
      return {
        'schema': 1,
        'source': 'ip_helper',
        'elapsed_ms': 5,
        'adapters': rows
      };
    });
  }

  setUp(() {
    api = WakeApi(
        baseUri: () async => Uri.parse('https://example.test'),
        accountToken: () async => 'a');
    service = WindowsWakeService(
        api: api,
        storage: const FlutterSecureStorage(),
        run: (_, __) async => ProcessResult(0, 0, '', ''));
  });
  tearDown(() {
    api.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('原生物理接口保留中文名称和多个可选网卡', () async {
    respond([row('board'), row('usb', mac: '02-11-22-33-44-56')]);
    final result = await service.adapters();
    expect(result.map((a) => a.id), ['board', 'usb']);
    expect(result.first.name, '中文以太网 board');
    expect(result.first.mac, '02:11:22:33:44:55');
  });
  test('排除虚拟有线与无效 MAC，无线不能作为有线', () async {
    respond([
      row('virtual', hardware: false),
      row('wifi', type: 71),
      row('invalid', mac: '00-00-00-00-00-00'),
      row('multicast', mac: '01-11-22-33-44-55'),
      row('disconnected', connected: false)
    ]);
    final result = await service.adapters();
    expect(result.where((a) => a.wired).map((a) => a.id), ['disconnected']);
    expect(result.firstWhere((a) => a.id == 'disconnected').connected, false);
    expect(result.firstWhere((a) => a.id == 'wifi').wired, false);
  });
  test('原生查询失败不能返回空网卡列表', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(
                code: 'adapter_query',
                details: {'api': 'GetAdaptersAddresses', 'code': 5}));
    await expectLater(service.adapters(), throwsA(isA<WakeApiException>()));
  });
  test('无接口才返回空列表', () async {
    respond([]);
    expect(await service.adapters(), isEmpty);
  });
  test('原生响应格式损坏不能当成没有网卡', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel, (_) async => {'schema': 2, 'adapters': []});
    await expectLater(service.adapters(), throwsA(isA<WakeApiException>()));
  });
}
