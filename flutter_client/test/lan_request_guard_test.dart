import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/utils/lan_request_guard.dart';

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.forEach((request) => guardLanRequest(request, () async {
          final body = await utf8.decoder.bind(request).join();
          final payload = jsonDecode(body) as Map<String, dynamic>;
          if (payload['boom'] == true) throw StateError('handler failed');
          request.response.write(payload['deviceId'] as String);
          await request.response.close();
        }));
  });

  tearDown(() => server.close(force: true));

  Future<String> rawPost(String body) async {
    final socket =
        await Socket.connect(InternetAddress.loopbackIPv4, server.port);
    final bytes = utf8.encode(body);
    socket.write('POST /session/trust HTTP/1.1\r\nHost: test\r\n'
        'Connection: close\r\nContent-Length: ${bytes.length}\r\n\r\n');
    socket.add(bytes);
    await socket.flush();
    final reply = await utf8.decoder
        .bind(socket)
        .join()
        .timeout(const Duration(seconds: 3));
    socket.destroy();
    return reply.split('\r\n').first;
  }

  test('空请求体、非 JSON 与字段类型错误都返回 400 而不是挂起连接', () async {
    expect(await rawPost(''), 'HTTP/1.1 400 Bad Request');
    expect(await rawPost('not json'), 'HTTP/1.1 400 Bad Request');
    expect(await rawPost('{"deviceId": 42}'), 'HTTP/1.1 400 Bad Request');
    expect(await rawPost('[]'), 'HTTP/1.1 400 Bad Request');
  });

  test('处理异常返回 500，之后的正常请求继续可用', () async {
    expect(
        await rawPost('{"boom": true}'), 'HTTP/1.1 500 Internal Server Error');
    expect(await rawPost('{"deviceId": "123"}'), 'HTTP/1.1 200 OK');
  });
}
