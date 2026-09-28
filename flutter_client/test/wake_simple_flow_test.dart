import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rdesk/src/models/wake.dart';
import 'package:rdesk/src/providers/wake_provider.dart';
import 'package:rdesk/src/services/desktop_wake_agent.dart';
import 'package:rdesk/src/services/wake_api.dart';
import 'package:rdesk/src/services/windows_wake_service.dart';
import 'wake_api_test.dart' show RealHttp;
import 'wake_provider_test.dart' show TestAgent;

/// In-memory stand-in for the account's /api/wake routes.
class FakeWakeServer {
  late HttpServer server;
  final paths = <String>[];
  List<Map<String, Object?>> agents = [];
  List<Map<String, Object?>> targets = [];

  Uri get base => Uri.parse('http://127.0.0.1:${server.port}');

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      final raw = await utf8.decoder.bind(r).join();
      final body = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw) as Map;
      paths.add('${r.method} ${r.uri.path}');
      Object reply = <String, Object>{};
      final path = r.uri.path;
      if (r.method == 'GET' && path == '/api/wake/agents') {
        reply = {'agents': agents};
      } else if (r.method == 'GET' && path == '/api/wake/targets') {
        reply = {'targets': targets};
      } else if (r.method == 'GET' && path == '/api/wake/requests') {
        reply = {'requests': []};
      } else if (r.method == 'POST' && path == '/api/wake/targets') {
        targets.add({
          'id': 't1',
          'name': body['name'],
          'device_id': body['device_id'],
          'mac': body['mac'],
          'agent_id': body['agent_id'],
          'revision': 1,
          'setup_complete': true,
        });
        reply = {'id': 't1', 'token': 'target-token'};
      } else if (r.method == 'PUT' && path.startsWith('/api/wake/targets/')) {
        final t = targets.first;
        t['agent_id'] = body['agent_id'];
        t['agent_online'] = agents
            .any((a) => a['id'] == body['agent_id'] && a['online'] == true);
        reply = t;
      } else if (r.method == 'POST' && path == '/api/wake/requests') {
        reply = {
          'id': 'r1',
          'target_id': body['target_id'],
          'phase': 'queued',
          'created_at_ms': 1,
        };
      } else if (path.endsWith('/heartbeat')) {
        reply = {'ok': true};
      }
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode(reply));
      await r.response.close();
    });
  }
}

Map<String, Object?> agentJson(String id, String name,
        {bool online = true, int seen = 0}) =>
    {
      'id': id,
      'name': name,
      'online': online,
      'enabled': true,
      'last_seen_ms': seen
    };

void main() {
  late FakeWakeServer fake;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    HttpOverrides.global = RealHttp();
    fake = FakeWakeServer();
    await fake.start();
  });
  tearDown(() async {
    HttpOverrides.global = null;
    await fake.server.close(force: true);
  });

  WakeApi api() =>
      WakeApi(baseUri: () async => fake.base, accountToken: () async => 'acct');

  group('开机时家中助手自动切换', () {
    test('绑定的助手离线时，改用在线助手再发送开机', () async {
      fake.agents = [
        agentJson('old', '旧手机', online: false),
        agentJson('mac', '家中 Mac'),
      ];
      fake.targets = [
        {
          'id': 't1',
          'name': '书房电脑',
          'device_id': '552910384',
          'mac': '00:11:22:33:44:55',
          'agent_id': 'old',
          'agent_online': false,
          'revision': 1,
        }
      ];
      final wake = WakeProvider(api: api(), agent: TestAgent());
      addTearDown(wake.dispose);
      await wake.bindAccount('user', 'server');
      await wake.refresh();
      expect(await wake.wake(wake.targets.single), isTrue);
      expect(fake.paths, contains('PUT /api/wake/targets/t1'));
      expect(fake.paths.last, 'POST /api/wake/requests');
      expect(fake.targets.single['agent_id'], 'mac');
    });

    test('家中没有在线助手时明确提示，不发送请求', () async {
      fake.agents = [agentJson('old', '旧手机', online: false)];
      fake.targets = [
        {
          'id': 't1',
          'name': '书房电脑',
          'device_id': '552910384',
          'mac': '00:11:22:33:44:55',
          'agent_id': 'old',
          'agent_online': false,
          'revision': 1,
        }
      ];
      final wake = WakeProvider(api: api(), agent: TestAgent());
      addTearDown(wake.dispose);
      await wake.bindAccount('user', 'server');
      await wake.refresh();
      expect(await wake.wake(wake.targets.single), isFalse);
      expect(wake.error, contains('没有在线的开机助手'));
      expect(fake.paths, isNot(contains('POST /api/wake/requests')));
    });
  });

  group('Windows 一键开启远程开机', () {
    WakeProvider windowsWake() => WakeProvider(
        api: api(),
        agent: TestAgent(),
        windows: WindowsWakeService(
            api: api(), storage: const FlutterSecureStorage()));

    test('有在线助手时直接登记，优先在线且最近活跃的助手', () async {
      fake.agents = [
        agentJson('phone', '家中安卓手机', online: false, seen: 50),
        agentJson('mac', '家中 Mac', seen: 10),
      ];
      final wake = windowsWake();
      addTearDown(wake.dispose);
      await wake.bindAccount('user', 'server');
      expect(
          await wake.enableLocalWake(
              deviceId: '552910384', name: '书房电脑', mac: '00:11:22:33:44:55'),
          isTrue);
      expect(fake.targets.single['agent_id'], 'mac');
      expect(wake.localWakePending, isFalse);
      expect(wake.targetForDevice('552910384'), isNotNull);
    });

    test('还没有助手时记住开启意图，助手出现后自动完成登记', () async {
      final wake = windowsWake();
      addTearDown(wake.dispose);
      await wake.bindAccount('user', 'server');
      expect(
          await wake.enableLocalWake(
              deviceId: '552910384', name: '书房电脑', mac: '00:11:22:33:44:55'),
          isTrue);
      expect(wake.localWakePending, isTrue);
      expect(fake.targets, isEmpty);

      fake.agents = [agentJson('phone', '家中安卓手机')];
      await wake.refresh();
      for (var i = 0; i < 20 && fake.targets.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(fake.targets.single['agent_id'], 'phone');
      expect(fake.targets.single['device_id'], '552910384');
      expect(wake.localWakePending, isFalse);
    });

    test('关闭远程开机会移除这台电脑并清除等待状态', () async {
      final wake = windowsWake();
      addTearDown(wake.dispose);
      await wake.bindAccount('user', 'server');
      await wake.enableLocalWake(
          deviceId: '552910384', name: '书房电脑', mac: '00:11:22:33:44:55');
      expect(wake.localWakePending, isTrue);
      expect(await wake.disableLocalWake('552910384'), isTrue);
      expect(wake.localWakePending, isFalse);
      fake.agents = [agentJson('phone', '家中安卓手机')];
      await wake.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(fake.targets, isEmpty);
    });
  });

  group('Mac 助手自动选择家庭网络', () {
    DesktopWakeNetwork n(String name, String cidr) =>
        DesktopWakeNetwork(name, cidr, '02:00:00:00:00:00');

    test('忽略虚拟网桥和 VPN，只剩一个物理网卡时自动选中', () {
      final picked = pickHomeNetwork([
        n('en0', '192.168.0.152/24'),
        n('bridge100', '10.211.55.2/24'),
        n('utun4', '10.8.0.2/24'),
      ]);
      expect(picked?.name, 'en0');
    });

    test('多个物理网卡无法判断时交给用户选择', () {
      expect(
          pickHomeNetwork([
            n('en0', '192.168.0.152/24'),
            n('en7', '192.168.31.20/24'),
          ]),
          isNull);
    });
  });

  test('开机请求阶段文案覆盖所有阶段', () {
    for (final phase in WakePhase.values) {
      expect(wakePhaseLabel(phase), isNotEmpty);
    }
  });
}
