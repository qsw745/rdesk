import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rdesk/src/providers/auth_provider.dart';
import 'wake_api_test.dart' show RealHttp;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('注销失败保留助手，注销成功即使本机停止报错也清理账号', () async {
    HttpOverrides.global = RealHttp();
    FlutterSecureStorage.setMockInitialValues({});
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    bool failDelete = true;
    server.listen((request) async {
      await request.drain<void>();
      if (request.uri.path == '/api/account/delete') {
        request.response.statusCode = failDelete ? 500 : 200;
        request.response.write(jsonEncode(
            failDelete ? {'message': 'storage failed'} : {'ok': true}));
      } else {
        request.response.write('{"devices":[]}');
      }
      await request.response.close();
    });
    SharedPreferences.setMockInitialValues({
      'rdesk.account_token': 'token',
      'rdesk.account_user_id': 'user',
      'rdesk.account_username': 'test',
      'rdesk.account_display_name': 'test',
      'rdesk.signaling_server': 'http://127.0.0.1:${server.port}'
    });
    final auth = AuthProvider();
    int stops = 0;
    auth.beforeAccountExit = () async {
      stops++;
      throw StateError('native stop failed');
    };
    try {
      await auth.initialize();
      expect(auth.isLoggedIn, true);
      expect(await auth.deleteAccount('password'), false);
      expect(stops, 0);
      expect(auth.isLoggedIn, true);
      failDelete = false;
      expect(await auth.deleteAccount('password'), true);
      expect(stops, 1);
      expect(auth.isLoggedIn, false);
      expect(auth.busy, false);
    } finally {
      auth.dispose();
      await server.close(force: true);
      HttpOverrides.global = null;
    }
  });
}
