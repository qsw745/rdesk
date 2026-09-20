import 'dart:async';
import 'package:rdesk/src/services/wake_api.dart';
import 'package:rdesk/src/services/wake_pairing_vault.dart';
import 'package:rdesk/src/providers/wake_pairing_provider.dart';
import 'package:rdesk/src/models/wake.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/models/wake_pairing.dart';

class TestVault implements WakePairingVault {
  Map<String, dynamic>? data;
  bool failSave = false;
  String? promoted;
  WakeEnrollment? known;
  @override
  Future<WakeEnrollment?> enrollment(String user, Uri endpoint) async => known;
  @override
  Future<Map<String, dynamic>?> read(String user, Uri endpoint) async => data;
  @override
  Future<void> save(
      String user, Uri endpoint, Map<String, Object?> value) async {
    if (failSave) throw StateError('locked');
    data = Map<String, dynamic>.from(value);
  }

  @override
  Future<void> promote(
      String user, Uri endpoint, String id, String token) async {
    promoted = token;
  }

  @override
  Future<void> clear(String user, Uri endpoint) async {
    data = null;
  }
}

class PairApi extends WakeApi {
  PairApi()
      : super(
            baseUri: () async => Uri.parse('https://relay.test'),
            accountToken: () async => 'account');
  String state = 'pending';
  int polls = 0, claims = 0, cancels = 0;
  bool lostReply = false,
      gone = false,
      noTargets = false,
      badHeartbeat = false,
      listFails = false;
  int creates = 0, scopes = 0;
  List<String> tokens = [];
  Completer<Map<String, dynamic>>? barrier;
  @override
  Future<WakeApi> scoped() async {
    scopes++;
    return this;
  }

  @override
  void close() {}
  @override
  Future<WakePairingSession> createPairing(
      {required String name,
      required String deviceId,
      required String mac}) async {
    creates++;
    return WakePairingSession(
        id: 'a' * 32,
        qrProof: 'b' * 64,
        desktopProof: 'c' * 64,
        manualCode: 'ABCDABCDABCDABCD',
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 300000);
  }

  @override
  Future<Map<String, dynamic>> pairingStatus(WakePairingSession s) async {
    polls++;
    if (gone) throw const WakeApiException('expired', '过期', 410);
    return barrier?.future ?? Future.value({'state': state});
  }

  @override
  Future<String> claimPairing(WakePairingSession s, String token) async {
    claims++;
    tokens.add(token);
    if (lostReply) {
      lostReply = false;
      throw const WakeApiException('network', '断网');
    }
    return 'target';
  }

  @override
  Future<void> cancelPairings() async {
    cancels++;
  }

  @override
  Future<void> cancelPairing(WakePairingSession s) async {}
  @override
  Future<List<WakeTarget>> targets() async {
    if (listFails) throw const WakeApiException('network', '断网');
    return noTargets
        ? []
        : [
            const WakeTarget(
                id: 'target',
                name: 'pc',
                deviceId: 'pc',
                mac: '02:11:22:33:44:55',
                agentId: '',
                online: false,
                agentOnline: false,
                revision: 1,
                setupComplete: false)
          ];
  }

  @override
  Future<void> targetHeartbeat(String id, String token) async {
    if (badHeartbeat)
      throw const WakeApiException('unauthorized', '凭据已失效', 401);
    expect(token, tokens.first);
  }
}

Future<WakePairingProvider> started(PairApi api, TestVault vault) async {
  final p = WakePairingProvider(api: api, vault: vault);
  p.bindAccount('owner', 'https://relay.test');
  await p.start(name: 'pc', deviceId: 'pc', mac: '02:11:22:33:44:55');
  return p;
}

void main() {
  test('未领取的候选过期并确认目标不存在后允许新配对', () async {
    final api = PairApi()
      ..state = 'confirmed'
      ..lostReply = true
      ..noTargets = true;
    final vault = TestVault();
    final p = await started(api, vault);
    addTearDown(p.dispose);
    await p.poll();
    api.gone = true;
    await p.poll();
    expect(p.phase, PairingPhase.expired);
    await p.start(name: 'pc', deviceId: 'pc', mac: '02:11:22:33:44:55');
    expect(api.creates, 2);
    expect(vault.data?['candidate_token'], isNull);
  });
  test('目标查询断网不能丢弃未确定的候选', () async {
    final api = PairApi()
      ..state = 'confirmed'
      ..lostReply = true;
    final vault = TestVault();
    final p = await started(api, vault);
    addTearDown(p.dispose);
    await p.poll();
    final token = vault.data!['candidate_token'];
    api.gone = true;
    api.listFails = true;
    await p.start(name: 'pc', deviceId: 'pc', mac: '02:11:22:33:44:55');
    expect(api.creates, 1);
    expect(vault.data!['candidate_token'], token);
  });
  test('旧凭据失效不显示配对成功', () async {
    final api = PairApi()
      ..badHeartbeat = true
      ..noTargets = true;
    final vault = TestVault()..known = const WakeEnrollment('deleted', 'old');
    final p = WakePairingProvider(api: api, vault: vault)
      ..bindAccount('user', 'server');
    addTearDown(p.dispose);
    await p.restore();
    expect(p.phase, PairingPhase.failed);
    expect(p.targetId, isNull);
  });
  test('同账号令牌更新会重新建立请求作用域并恢复配对', () async {
    final api = PairApi();
    final vault = TestVault();
    final p = WakePairingProvider(api: api, vault: vault)
      ..bindAccount('user', 'server', token: 'one');
    addTearDown(p.dispose);
    await p.start(name: 'pc', deviceId: 'pc', mac: '02:11:22:33:44:55');
    p.bindAccount('user', 'server', token: 'two');
    await p.restore();
    expect(api.scopes, 2);
    expect(p.phase, PairingPhase.waiting);
  });
  test('到期后停止等待，刷新不会延长二维码有效期', () async {
    var clock = DateTime.now();
    final api = PairApi();
    final p =
        WakePairingProvider(api: api, vault: TestVault(), now: () => clock)
          ..bindAccount('user', 'server');
    addTearDown(p.dispose);
    await p.start(name: 'pc', deviceId: 'pc', mac: '02:11:22:33:44:55');
    final deadline = p.session!.expiresAtMs;
    clock = clock.add(const Duration(minutes: 6));
    await p.poll();
    expect(p.phase, PairingPhase.expired);
    expect(p.secondsRemaining, 0);
    expect(p.session!.expiresAtMs, deadline);
    expect(api.polls, 0);
  });

  test('更新或重启后恢复原有本机绑定，避免再生成二维码', () async {
    final api = PairApi()..tokens = ['existing-token'];
    final vault = TestVault()
      ..known = const WakeEnrollment('existing', 'existing-token');
    final p = WakePairingProvider(api: api, vault: vault)
      ..bindAccount('user', 'https://relay.test');
    addTearDown(p.dispose);
    await p.restore();
    expect(p.phase, PairingPhase.paired);
    expect(p.targetId, 'existing');
    expect(api.claims, 0);
  });

  test('未知领取结果时重新生成不能覆盖已保存的候选令牌', () async {
    final api = PairApi()
      ..state = 'confirmed'
      ..lostReply = true;
    final vault = TestVault();
    final p = await started(api, vault);
    addTearDown(p.dispose);
    await p.poll();
    final token = api.tokens.single;
    await p.start(name: 'pc', deviceId: 'pc', mac: '02:11:22:33:44:55');
    expect(vault.promoted, token);
    expect(api.tokens.every((t) => t == token), isTrue);
  });

  test('领取前安全保存，响应丢失后重试同一令牌且不生成第二个配对', () async {
    final api = PairApi()
      ..state = 'confirmed'
      ..lostReply = true;
    final vault = TestVault();
    final p = await started(api, vault);
    addTearDown(p.dispose);
    await p.poll();
    expect(api.claims, 1);
    expect(vault.data!['candidate_token'], api.tokens.first);
    expect(vault.promoted, isNull);
    await p.poll();
    expect(p.phase, PairingPhase.paired);
    expect(api.tokens[0], api.tokens[1]);
    expect(vault.promoted, api.tokens.first);
    expect(vault.data, isNull);
  });
  test('安全存储失败不会把永久令牌提交给服务器', () async {
    final api = PairApi()..state = 'confirmed';
    final vault = TestVault();
    final p = await started(api, vault);
    addTearDown(p.dispose);
    vault.failSave = true;
    await p.poll();
    expect(api.claims, 0);
    expect(p.phase, PairingPhase.failed);
  });
  test('换服务器或退出后，延迟确认响应不得领取或更新状态', () async {
    for (final exit in [false, true]) {
      final api = PairApi()..barrier = Completer();
      final p = await started(api, TestVault());
      final pending = p.poll();
      await Future<void>.delayed(Duration.zero);
      if (exit) {
        await p.cancelForExit();
      } else {
        p.bindAccount('owner', 'https://other.test');
      }
      api.barrier!.complete({'state': 'confirmed'});
      await pending;
      expect(api.claims, 0);
      expect(p.phase, PairingPhase.idle);
      expect(p.session, isNull);
      p.dispose();
    }
  });
  test('领取成功后服务重启，候选凭据验证通过才恢复绑定', () async {
    final api = PairApi()
      ..state = 'confirmed'
      ..lostReply = true;
    final vault = TestVault();
    final first = await started(api, vault);
    await first.poll();
    first.dispose();
    api.gone = true;
    final p = WakePairingProvider(api: api, vault: vault)
      ..bindAccount('owner', 'https://relay.test');
    addTearDown(p.dispose);
    await p.restore();
    expect(p.phase, PairingPhase.paired);
    expect(p.targetId, 'target');
    expect(api.claims, 1);
  });
  testWidgets('离开页面或切后台停止轮询，回到前台只发起一次查询', (tester) async {
    final api = PairApi();
    final p = await started(api, TestVault());
    p.setVisible(true);
    await tester.pump();
    final count = api.polls;
    p.setVisible(false);
    await tester.pump(const Duration(seconds: 8));
    expect(api.polls, count);
    p.setVisible(true);
    await tester.pump();
    expect(api.polls, count + 1);
    p.dispose();
  });

  test('二维码只接受封闭格式，拒绝 URL、附加地址、错误版本与超长输入', () {
    final good = {
      'type': 'rdesk-wake-pair',
      'version': 1,
      'id': 'a' * 32,
      'proof': 'b' * 64
    };
    final code = WakePairingCode.parse(jsonEncode(good));
    expect(code.id, 'a' * 32);
    expect(code.resolveBody, {'id': 'a' * 32, 'qr_proof': 'b' * 64});
    for (final value in [
      'https://example.test',
      jsonEncode({...good, 'server': 'https://attacker.test'}),
      jsonEncode({...good, 'version': 2}),
      jsonEncode({...good, 'proof': 'secret'}),
      'x' * 2000
    ]) {
      expect(() => WakePairingCode.parse(value), throwsFormatException);
    }
  });
  test('二维码不含电脑证明、手动码和永久凭据', () {
    final session = WakePairingSession(
        id: 'a' * 32,
        qrProof: 'b' * 64,
        desktopProof: 'c' * 64,
        manualCode: 'ABCDABCDABCDABCD',
        expiresAtMs: 123);
    expect(jsonDecode(session.qrText).keys,
        unorderedEquals(['type', 'version', 'id', 'proof']));
    expect(session.qrText, isNot(contains(session.desktopProof)));
    expect(session.qrText, isNot(contains(session.manualCode)));
  });
}
