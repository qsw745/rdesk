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
      calls++;
      entered.complete();
      await release.future;
      request.response.write(jsonEncode({
        'id': 'request',
        'target_id': 'pc',
        'phase': 'sent',
        'created_at_ms': 1
      }));
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
}
