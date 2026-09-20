import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/services/wake_api.dart';
import 'package:rdesk/src/models/wake.dart';

class RealHttp extends HttpOverrides {
  @override
  // Flutter tests otherwise replace real local HTTP with a 400 stub.
  // ignore: unnecessary_overrides
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('开机配置通过账号鉴权读取并在每次请求更新令牌', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final auth = <String?>[];
    final requests = server.listen((r) async {
      auth.add(r.headers.value(HttpHeaders.authorizationHeader));
      expect(r.uri.query, '');
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode({
        'targets': [
          {
            'id': 'pc',
            'name': '电脑',
            'device_id': 'pc-device',
            'mac': '02:11:22:33:44:55',
            'agent_id': 'phone',
            'revision': 1,
            'online': false,
            'agent_online': true
          }
        ]
      }));
      await r.response.close();
    });
    addTearDown(requests.cancel);
    await HttpOverrides.runWithHttpOverrides(() async {
      var token = 'first';
      final api = WakeApi(
          baseUri: () async => Uri.parse('http://127.0.0.1:${server.port}'),
          accountToken: () async => token);
      addTearDown(api.close);
      expect((await api.targets()).single.id, 'pc');
      token = 'second';
      await api.targets();
      expect(auth, ['Bearer first', 'Bearer second']);
    }, RealHttp());
  });
  test('发送及未知状态不会被识别为开机成功', () {
    final base = {'id': 'r', 'target_id': 'pc', 'created_at_ms': 1};
    expect(
        WakeRequest.fromJson({...base, 'phase': 'sent'}).phase, WakePhase.sent);
    expect(WakeRequest.fromJson({...base, 'phase': 'future-state'}).phase,
        WakePhase.unknown);
  });
  test('旧服务端及重定向返回明确错误且不跟随', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var count = 0;
    final sub = server.listen((r) async {
      count++;
      r.response.statusCode = count == 1 ? 404 : 302;
      r.response.headers
          .set('location', 'http://127.0.0.1:${server.port}/leak');
      await r.response.close();
    });
    addTearDown(sub.cancel);
    await HttpOverrides.runWithHttpOverrides(() async {
      final api = WakeApi(
          baseUri: () async => Uri.parse('http://127.0.0.1:${server.port}'),
          accountToken: () async => 'secret');
      addTearDown(api.close);
      await expectLater(
          api.targets(),
          throwsA(isA<WakeApiException>()
              .having((e) => e.code, 'code', 'unsupported')));
      await expectLater(
          api.targets(),
          throwsA(isA<WakeApiException>()
              .having((e) => e.statusCode, 'status', 302)));
      expect(count, 2);
    }, RealHttp());
  });
}
