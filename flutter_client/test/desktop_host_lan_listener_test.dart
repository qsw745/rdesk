import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/providers/desktop_host_provider.dart';
import 'package:rdesk/src/services/incoming_file_store.dart';
import 'package:rdesk/src/services/rdesk_bridge_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/recording_host_service.dart';

Future<void> eventually(bool Function() check) async {
  final deadline = DateTime.now().add(const Duration(seconds: 4));
  while (!check() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(check(), isTrue);
}

Future<bool> accepts(int port) async {
  try {
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port,
        timeout: const Duration(seconds: 1));
    socket.destroy();
    return true;
  } on SocketException {
    return false;
  }
}

Future<int> freePort() async {
  final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close();
  return port;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.qsw.rdesk/desktop_host');
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late HttpServer relay;
  late DesktopHostProvider host;
  late RecordingHostService service;
  late Directory downloads;
  late int port;
  // What the fake relay hands the host next, and the file it holds for it.
  Map<String, Object?>? relayCommand;
  List<int>? relayFile;
  final relayResults = <Map<String, dynamic>>[];
  String? captureError;
  var rotations = 0;

  Future<({int status, String body})> call(String path,
      {Map<String, Object>? body, String? token}) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('http://127.0.0.1:$port$path').replace(
          queryParameters: token == null ? null : {'session_token': token});
      final req = await client.openUrl(body == null ? 'GET' : 'POST', uri);
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final response = await req.close();
      final text = await utf8.decoder.bind(response).join().catchError(
          (Object _) => '',
          test: (error) => error is FormatException);
      return (status: response.statusCode, body: text);
    } finally {
      client.close(force: true);
    }
  }

  Future<String> authenticate() async {
    final response = await call('/session/trust', body: {
      'deviceId': '222333444',
      'hostname': 'test viewer',
      'peerOs': 'ios',
      'password': 'test-password',
    });
    expect(response.status, 200);
    return (jsonDecode(response.body) as Map)['session_token'] as String;
  }

  Future<void> hostReady() async {
    await host.initialize();
    await host.startHosting();
    await eventually(() => host.lanRelayEndpoint != null);
  }

  setUp(() async {
    HttpOverrides.global = null;
    relay = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(relay.forEach((req) async {
      final received = await utf8.decoder.bind(req).join();
      if (req.uri.path == '/api/preview/host/control/result') {
        relayResults.add(jsonDecode(received) as Map<String, dynamic>);
      }
      req.response.headers.contentType = ContentType.json;
      if (req.uri.path == '/api/preview/host/control/poll') {
        final command = relayCommand;
        relayCommand = null;
        if (command == null) {
          req.response.statusCode = 204;
        } else {
          req.response.write(jsonEncode(command));
        }
      } else if (req.uri.path.startsWith('/api/file/host/download/')) {
        final file = relayFile;
        relayFile = null;
        if (file == null ||
            req.uri.queryParameters['host_token'] != 'test-host') {
          req.response.statusCode = 404;
        } else {
          req.response.headers.contentType = ContentType.binary;
          req.response.add(file);
        }
      } else if (req.uri.path == '/api/preview/host/control/result') {
        req.response.write('{}');
      } else {
        req.response.write(req.uri.path == '/api/preview/register'
            ? '{"host_token":"test-host"}'
            : '{}');
      }
      try {
        await req.response.close();
      } catch (_) {}
    }));
    SharedPreferences.setMockInitialValues({
      'rdesk.device_id': '111222333',
      'rdesk.temp_password': 'test-password',
      'rdesk.signaling_server': 'http://127.0.0.1:${relay.port}',
    });
    RdeskBridgeService.instance.closeHostClient();
    messenger.setMockMethodCallHandler(secure, (_) async => null);
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getPermissionState') {
        return {'screenRecordingGranted': true, 'accessibilityGranted': true};
      }
      if (call.method == 'captureScreen') {
        final error = captureError;
        if (error != null) throw PlatformException(code: error);
        return {
          'bytes': Uint8List.fromList([1, 2, 3]),
          'width': 3,
          'height': 1
        };
      }
      return null;
    });
    captureError = null;
    rotations = 0;
    port = await freePort();
    service = RecordingHostService();
    downloads = await Directory.systemTemp.createTemp('rdesk-host-test');
    relayCommand = null;
    relayFile = null;
    relayResults.clear();
    host = DesktopHostProvider(
        lanPort: port,
        service: service,
        incomingFiles: IncomingFileStore(directory: () async => downloads),
        rotateTemporaryPassword: () async {
          rotations++;
          await RdeskBridgeService.instance.generateTemporaryPassword();
        });
  });

  tearDown(() async {
    host.dispose();
    await relay.close(force: true);
    if (await downloads.exists()) await downloads.delete(recursive: true);
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(secure, null);
  });

  test('多条路径同时建立监听时只绑定一次，关闭后不残留', () async {
    await host.initialize();
    // At launch the availability loop and the hosting transition overlap.
    final starting = host.startHosting();
    await Future.wait([
      starting,
      host.debugEnsureLanRelay(),
      host.debugEnsureLanRelay(),
    ]);
    await eventually(() => host.lanRelayEndpoint != null);

    expect(host.lanRelayEndpoint, endsWith(':$port'),
        reason: 'a second bind fell back to another port');

    await host.stopHosting();
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(await accepts(port), isFalse,
        reason: 'a listener stayed open after hosting was switched off');
  }, skip: !(Platform.isMacOS || Platform.isWindows));

  test('建立监听途中关闭再开启，最终仍只有当前这一次的监听', () async {
    await host.initialize();
    final first = host.startHosting();
    final stopping = host.stopHosting();
    final second = host.startHosting();
    await Future.wait([first, stopping, second]);
    await eventually(() => host.lanRelayEndpoint != null);

    expect(host.lanRelayEndpoint, endsWith(':$port'));
    expect(await accepts(port), isTrue);

    await host.stopHosting();
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(await accepts(port), isFalse);
  }, skip: !(Platform.isMacOS || Platform.isWindows));

  test('关闭被控后局域网端口不再接受连接', () async {
    await host.initialize();
    await host.startHosting();
    await eventually(() => host.lanRelayEndpoint != null);
    expect(await accepts(port), isTrue);

    await host.stopHosting();
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(await accepts(port), isFalse);
  }, skip: !(Platform.isMacOS || Platform.isWindows));

  test('只发输入不取画面的会话也算正在被访问，关闭会话后结束', () async {
    await hostReady();
    final token = await authenticate();
    expect(host.remoteAccessActive, isFalse,
        reason: 'authenticating alone is not access yet');

    final tap = await call('/input/tap',
        token: token, body: {'x': 0.5, 'y': 0.5});
    expect(tap.status, 200);
    expect(service.inputs, ['tap 0.5,0.5']);
    expect(host.activeViewerCount, 0);
    expect(host.remoteAccessActive, isTrue);

    await call('/session/close', token: token, body: {});
    expect(host.remoteAccessActive, isFalse);
  }, skip: !(Platform.isMacOS || Platform.isWindows));

  test('读取剪贴板同样算正在被访问', () async {
    await hostReady();
    final token = await authenticate();

    await call('/clipboard/get', token: token);

    expect(service.inputs, ['clipboardGet']);
    expect(host.remoteAccessActive, isTrue);
  }, skip: !(Platform.isMacOS || Platform.isWindows));

  test('锁屏后不再返回锁屏前的画面', () async {
    await hostReady();
    final token = await authenticate();
    var status = 0;
    await eventually(() {
      unawaited(call('/frame.jpg', token: token).then((r) => status = r.status));
      return status == 200;
    });

    captureError = 'SESSION_LOCKED';
    await eventually(() {
      unawaited(call('/frame.jpg', token: token).then((r) => status = r.status));
      return status == 503;
    });

    expect(host.previewFrame, isNull);
    expect(host.error, contains('锁屏'));
  }, skip: !(Platform.isMacOS || Platform.isWindows));

  test('从托盘断开会收回凭据：旧令牌、旧验证码和受信设备全部失效', () async {
    await hostReady();
    final token = await authenticate();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('rdesk.trusted_incoming_viewers'), isNotNull);

    await host.revokeAccessAndDisconnect();
    await eventually(() => host.lanRelayEndpoint != null);

    expect(rotations, 1);
    expect(prefs.getString('rdesk.temp_password'), isNot('test-password'));
    expect(prefs.getString('rdesk.trusted_incoming_viewers'), isNull);
    expect((await call('/frame.jpg', token: token)).status, 401);
    final retry = await call('/session/trust', body: {
      'deviceId': '222333444',
      'hostname': 'test viewer',
      'peerOs': 'ios',
      'password': 'test-password',
    });
    expect(retry.status, 401);
  }, skip: !(Platform.isMacOS || Platform.isWindows));

  test('路径拖动指令在桌面被控端有对应处理，不会落空', () async {
    await hostReady();
    final token = await authenticate();

    final ok = await call('/input/drag_path', token: token, body: {
      'points': [
        [0.1, 0.2],
        [0.2, 0.3],
        [0.5, 0.6],
      ],
    });
    final malformed =
        await call('/input/drag_path', token: token, body: {'points': 'x'});

    expect(ok.status, 200);
    expect(malformed.status, 400);
    expect(service.inputs, ['dragPath 3']);
  }, skip: !(Platform.isMacOS || Platform.isWindows));

  test('被控端记录是谁在访问、从何时开始，会话关闭后清除', () async {
    await hostReady();
    expect(host.currentViewers, isEmpty);
    expect(host.remoteAccessSince, isNull);
    final token = await authenticate();
    expect(host.currentViewers, isEmpty,
        reason: 'authenticated but has not done anything yet');

    await call('/input/tap', token: token, body: {'x': 0.5, 'y': 0.5});

    expect(host.currentViewers.single.name, 'test viewer');
    expect(host.currentViewers.single.platform, 'ios');
    expect(host.remoteAccessSince, isNotNull);

    await call('/session/close', token: token, body: {});

    expect(host.currentViewers, isEmpty);
    expect(host.remoteAccessSince, isNull);
  }, skip: !(Platform.isMacOS || Platform.isWindows));

  group('接收文件', () {
    Future<File> localFile(String name, List<int> bytes) async {
      final file = File('${downloads.parent.path}/rdesk-src-${port}_$name');
      await file.writeAsBytes(bytes);
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });
      return file;
    }

    test('局域网直连：观看端发送的文件保存到被控端的接收目录，结果如实返回', () async {
      await hostReady();
      final token = await authenticate();
      final source = await localFile('合同.txt', utf8.encode('hello'));
      RdeskBridgeService.instance.debugSetSessionEndpoint(
          'lan-session', Uri.parse('http://127.0.0.1:$port/frame.jpg'),
          sessionToken: token);

      final result = await RdeskBridgeService.instance
          .sendFileToHost('lan-session', source.path);

      expect(result.outcome, FileSendOutcome.saved);
      final saved = File('${downloads.path}/${result.savedAs}');
      expect(await saved.readAsString(), 'hello');
      expect(result.savedAs, endsWith('合同.txt'));
      expect(host.lastReceivedFile, result.savedAs);
    }, skip: !(Platform.isMacOS || Platform.isWindows));

    test('没有会话令牌不能向被控端写文件', () async {
      await hostReady();

      final response = await call('/files/upload?filename=x.txt', body: {});

      expect(response.status, 401);
      expect(downloads.listSync(), isEmpty);
    }, skip: !(Platform.isMacOS || Platform.isWindows));

    test('文件名里的路径不能把文件带出接收目录', () async {
      await hostReady();
      final token = await authenticate();
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.postUrl(Uri.parse(
          'http://127.0.0.1:$port/files/upload?session_token=$token'
          '&filename=${Uri.encodeQueryComponent('../../escaped.txt')}'));
      request.contentLength = 1;
      request.add([65]);
      final response = await request.close();
      await response.drain<void>();

      expect(response.statusCode, 200);
      expect(File('${downloads.path}/escaped.txt').existsSync(), isTrue);
      expect(File('${downloads.parent.path}/escaped.txt').existsSync(), isFalse);
    }, skip: !(Platform.isMacOS || Platform.isWindows));

    test('经中继：被控端取回文件并保存，再把结果回报给中继', () async {
      relayFile = utf8.encode('via relay');
      relayCommand = {
        'command_id': 'cmd-1',
        'kind': 'file_receive',
        'payload': {'file_id': 'file-1', 'filename': 'notes.txt', 'size': 9},
      };
      await hostReady();

      await eventually(() => relayResults.isNotEmpty);

      expect(relayResults.single['command_id'], 'cmd-1');
      expect(relayResults.single['ok'], true);
      expect(relayResults.single['text'], 'notes.txt');
      expect(await File('${downloads.path}/notes.txt').readAsString(),
          'via relay');
    }, skip: !(Platform.isMacOS || Platform.isWindows));

    test('中继上已经没有这个文件时回报失败，不留下空文件', () async {
      relayFile = null;
      relayCommand = {
        'command_id': 'cmd-2',
        'kind': 'file_receive',
        'payload': {'file_id': 'gone', 'filename': 'notes.txt', 'size': 9},
      };
      await hostReady();

      await eventually(() => relayResults.isNotEmpty);

      expect(relayResults.single['ok'], false);
      expect(downloads.listSync(), isEmpty);
    }, skip: !(Platform.isMacOS || Platform.isWindows));
  });
}
