import 'dart:io';

/// 保留产品发出的真实 URI，只在测试传输层把官方服务接到本地假服务器。
/// 未明确允许的外网目标直接失败，避免测试触及线上账号或被控端。
class OfficialServerHttp extends HttpOverrides {
  final int port;
  final void Function(Uri)? onRequest;
  OfficialServerHttp(this.port, {this.onRequest});

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _LocalClient(super.createHttpClient(context), port, onRequest);
}

class _LocalClient implements HttpClient {
  final HttpClient client;
  final int port;
  final void Function(Uri)? onRequest;
  _LocalClient(this.client, this.port, this.onRequest);

  Uri _destination(Uri uri) {
    onRequest?.call(uri);
    if (uri.origin == 'https://qisw.top') {
      return uri.replace(scheme: 'http', host: '127.0.0.1', port: port);
    }
    if (uri.host == '127.0.0.1' || uri.host == 'localhost') return uri;
    throw StateError('测试禁止外网请求：$uri');
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      client.openUrl(method, _destination(url));
  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);
  @override
  set connectionTimeout(Duration? value) => client.connectionTimeout = value;
  @override
  set idleTimeout(Duration value) => client.idleTimeout = value;
  @override
  void close({bool force = false}) => client.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
