import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rdesk/src/models/wake.dart';
import 'package:rdesk/src/providers/wake_provider.dart';
import 'package:rdesk/src/services/wake_agent_channel.dart';
import 'package:rdesk/src/services/wake_api.dart';
import 'wake_api_test.dart' show RealHttp;

class TestAgent extends WakeAgentChannel {
  int starts = 0, stops = 0;
  Future<void>? permissionBarrier;
  @override
  Future<void> prepare() async {
    await permissionBarrier;
  }

  @override
  Future<WakeAgentStatus> status() async => const WakeAgentStatus();
  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> start(
      {required String endpoint,
      required String ownerId,
      required String agentId,
      required String token}) async {
    starts++;
  }
}

class ResumableAgent extends TestAgent {
  static const lan = {
    'interface': 'en0',
    'ipv4_cidr': '192.168.31.20/24',
    'interface_hardware': 'aa:bb:cc:dd:ee:ff'
  };
  bool lanPresent = true;
  int selections = 0;
  @override
  Map<String, String>? get resumeNetwork => lan;
  @override
  Future<bool> selectResumeNetwork(Map<String, dynamic> saved) async {
    selections++;
    return lanPresent && lan.keys.every((k) => saved[k] == lan[k]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HttpOverrides.global = RealHttp();
  });
  tearDown(() {
    HttpOverrides.global = null;
  });
  test('等待通知权限时退出账号，之后授权也不能启动助手', () async {
    final permission = Completer<void>();
    final agent = TestAgent()..permissionBarrier = permission.future;
    final wake = WakeProvider(
        api: WakeApi(
            baseUri: () async => Uri.parse('https://example.test'),
            accountToken: () async => 'token'),
        agent: agent);
    addTearDown(wake.dispose);
    await wake.bindAccount('user', 'server');
    final enabling = wake.enableHelper('手机');
    await Future<void>.delayed(Duration.zero);
    await wake.stopForAccountExit();
    permission.complete();
    expect(await enabling, false);
    expect(agent.starts, 0);
    expect(wake.loggedIn, false);
  });
  test('停用和重新打开应用后启用同一个助手标识', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final paths = <String>[];
    server.listen((r) async {
      await r.drain<void>();
      paths.add('${r.method} ${r.uri.path}');
      Object body = <String, Object>{};
      if (r.method == 'POST' &&
          (r.uri.path.endsWith('/agents') || r.uri.path.endsWith('/enable'))) {
        body = {'id': 'stable', 'token': 'device-token'};
      } else if (r.method == 'GET') {
        body =
            r.uri.path.endsWith('/targets') ? {'targets': []} : {'agents': []};
      }
      r.response.write(jsonEncode(body));
      await r.response.close();
    });
    WakeProvider make() => WakeProvider(
        api: WakeApi(
            baseUri: () async => Uri.parse('http://127.0.0.1:${server.port}'),
            accountToken: () async => 'account'),
        agent: TestAgent());
    var wake = make();
    try {
      await wake.bindAccount('user', 'server');
      expect(await wake.enableHelper('手机'), true);
      expect(await wake.disableHelper(), true);
      wake.dispose();
      wake = make();
      await wake.bindAccount('user', 'server');
      expect(await wake.enableHelper('手机'), true);
      expect(paths.where((p) => p == 'POST /api/wake/agents').length, 1);
      expect(paths, contains('POST /api/wake/agents/stable/stop'));
      expect(paths, contains('POST /api/wake/agents/stable/enable'));
      expect(paths.any((p) => p.startsWith('DELETE')), false);
    } finally {
      wake.dispose();
      await server.close(force: true);
    }
  });
  test('退出后晚到的助手注册回包被撤销，不能启动本机服务', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final entered = Completer<void>(),
        release = Completer<void>(),
        revoked = Completer<void>();
    server.listen((request) async {
      await request.drain<void>();
      if (request.method == 'POST') {
        entered.complete();
        await release.future;
        request.response
            .write(jsonEncode({'id': 'helper', 'token': 'private'}));
      } else if (request.method == 'DELETE') {
        revoked.complete();
        request.response.write('{}');
      }
      await request.response.close();
    });
    final agent = TestAgent();
    final wake = WakeProvider(
        api: WakeApi(
            baseUri: () async => Uri.parse('http://127.0.0.1:${server.port}'),
            accountToken: () async => 'account'),
        agent: agent);
    addTearDown(() async {
      wake.dispose();
      await server.close(force: true);
    });
    await wake.bindAccount('user', 'server');
    final enabling = wake.enableHelper('家中手机');
    await entered.future.timeout(const Duration(seconds: 3));
    await wake.stopForAccountExit();
    release.complete();
    expect(await enabling, false);
    await revoked.future.timeout(const Duration(seconds: 3));
    expect(agent.starts, 0);
  });
  test('重复点击只提交一次，信号已发送不等于电脑上线', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    int calls = 0;
    final entered = Completer<void>(), release = Completer<void>();
    server.listen((request) async {
      await request.drain<void>();
      Object body;
      if (request.method == 'GET' && request.uri.path == '/api/wake/targets') {
        body = {
          'targets': [
            {
              'id': 'pc',
              'name': '电脑',
              'device_id': '123',
              'mac': '02:11:22:33:44:55',
              'agent_id': 'agent',
              'online': false,
              'agent_online': true,
              'setup_complete': true,
              'revision': 1
            }
          ]
        };
      } else if (request.method == 'GET' &&
          request.uri.path == '/api/wake/agents') {
        body = {
          'agents': [
            {'id': 'agent', 'name': '助手', 'enabled': true, 'online': true}
          ]
        };
      } else if (request.method == 'GET' &&
          request.uri.path == '/api/wake/requests') {
        body = {'requests': []};
      } else {
        expect(request.method, 'POST');
        expect(request.uri.path, '/api/wake/requests');
        calls++;
        entered.complete();
        await release.future;
        body = {
          'id': 'request',
          'target_id': 'pc',
          'phase': 'sent',
          'created_at_ms': 1
        };
      }
      request.response.write(jsonEncode(body));
      await request.response.close();
    });
    final wake = WakeProvider(
        api: WakeApi(
            baseUri: () async => Uri.parse('http://127.0.0.1:${server.port}'),
            accountToken: () async => 'account'),
        agent: TestAgent());
    addTearDown(() async {
      wake.dispose();
      await server.close(force: true);
    });
    await wake.bindAccount('user', 'server');
    const target = WakeTarget(
        id: 'pc',
        name: '电脑',
        deviceId: '123',
        mac: '02:11:22:33:44:55',
        agentId: 'agent',
        online: false,
        agentOnline: true,
        revision: 1);
    final first = wake.wake(target);
    await entered.future;
    expect(await wake.wake(target), false);
    release.complete();
    expect(await first, true);
    expect(calls, 1);
    expect(wake.history['pc']!.single.phase, WakePhase.sent);
    expect(
        wakePhaseLabel(wake.history['pc']!.single.phase), contains('等待电脑上线'));
    await wake.bindAccount('other', 'server');
    expect(wake.history, isEmpty);
  });
  test('服务器地址读取失败后恢复可重试，不锁死按钮', () async {
    bool fail = false;
    final wake = WakeProvider(
        api: WakeApi(
            baseUri: () async {
              if (fail) throw const WakeApiException('network', '网络故障');
              return Uri.parse('https://example.test');
            },
            accountToken: () async => 'account'),
        agent: TestAgent());
    addTearDown(wake.dispose);
    await wake.bindAccount('user', 'server');
    fail = true;
    expect(await wake.enableHelper('家中手机'), false);
    expect(wake.busy, false);
    expect(wake.error, '网络故障');
  });

  group('Mac 助手重新打开后自动恢复', () {
    late HttpServer server;
    late List<String> paths;
    var enableMissing = false;
    setUp(() async {
      paths = [];
      enableMissing = false;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        await r.drain<void>();
        paths.add('${r.method} ${r.uri.path}');
        Object body = <String, Object>{};
        if (r.uri.path.endsWith('/enable') && enableMissing) {
          r.response.statusCode = 404;
          body = {'code': 'not_found'};
        } else if (r.method == 'POST' &&
            (r.uri.path.endsWith('/agents') ||
                r.uri.path.endsWith('/enable'))) {
          body = {'id': 'stable', 'token': 'device-token'};
        } else if (r.method == 'GET') {
          body = r.uri.path.endsWith('/targets')
              ? {'targets': []}
              : {'agents': []};
        }
        r.response.write(jsonEncode(body));
        await r.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    WakeProvider make(TestAgent agent) => WakeProvider(
        api: WakeApi(
            baseUri: () async => Uri.parse('http://127.0.0.1:${server.port}'),
            accountToken: () async => 'account'),
        agent: agent);
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 300));

    test('同一家庭网络在场时沿用原助手身份自动启动', () async {
      final first = make(ResumableAgent());
      await first.bindAccount('user', 'server');
      expect(await first.enableHelper('家中 Mac'), true);
      first.dispose();

      final agent = ResumableAgent();
      final wake = make(agent);
      addTearDown(wake.dispose);
      await wake.bindAccount('user', 'server');
      await settle();
      expect(agent.starts, 1);
      expect(paths.where((p) => p == 'POST /api/wake/agents').length, 1);
      expect(paths, contains('POST /api/wake/agents/stable/enable'));
      expect(wake.error, isNull);
    });

    test('家庭网络不在场时不启动，并说明原因', () async {
      final first = make(ResumableAgent());
      await first.bindAccount('user', 'server');
      expect(await first.enableHelper('家中 Mac'), true);
      first.dispose();

      final agent = ResumableAgent()..lanPresent = false;
      final wake = make(agent);
      addTearDown(wake.dispose);
      await wake.bindAccount('user', 'server');
      await settle();
      expect(agent.selections, 1);
      expect(agent.starts, 0);
      expect(wake.error, contains('家庭网络当前不可用'));
    });

    test('主动停用或退出账号后不再自动恢复', () async {
      for (final exit in [true, false]) {
        final first = make(ResumableAgent());
        await first.bindAccount('user', 'server');
        expect(await first.enableHelper('家中 Mac'), true);
        if (exit) {
          await first.stopForAccountExit();
        } else {
          expect(await first.disableHelper(), true);
        }
        first.dispose();

        final agent = ResumableAgent();
        final wake = make(agent);
        await wake.bindAccount('user', 'server');
        await settle();
        expect(agent.selections, 0, reason: exit ? '退出账号' : '主动停用');
        expect(agent.starts, 0);
        wake.dispose();
      }
    });

    test('助手已在其他设备移除时不会自动新建', () async {
      final first = make(ResumableAgent());
      await first.bindAccount('user', 'server');
      expect(await first.enableHelper('家中 Mac'), true);
      first.dispose();
      enableMissing = true;

      final agent = ResumableAgent();
      final wake = make(agent);
      addTearDown(wake.dispose);
      await wake.bindAccount('user', 'server');
      await settle();
      expect(agent.starts, 0);
      expect(paths.where((p) => p == 'POST /api/wake/agents').length, 1);
      expect(wake.error, contains('已在其他设备移除'));

      final again = ResumableAgent();
      final later = make(again);
      addTearDown(later.dispose);
      await later.bindAccount('user', 'server');
      await settle();
      expect(again.selections, 0);
    });
  });
}
