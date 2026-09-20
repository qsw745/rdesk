import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rdesk/src/models/app_update.dart';
import 'package:rdesk/src/services/app_update_service.dart';
import 'package:rdesk/src/providers/app_update_provider.dart';

Map<String, dynamic> manifest(
    {String version = '2.2.1',
    int? build = 18,
    List<int> data = const [1, 2, 3]}) {
  final files = <String, dynamic>{};
  final platforms = <Map<String, dynamic>>[];
  for (final entry in {
    'windows': 'windows-x64-setup.exe',
    'android': 'android.apk',
    'macos': 'macos-arm64.dmg'
  }.entries) {
    final name = 'RDesk-$version-${entry.value}';
    files[name] = {
      'bytes': data.length,
      'sha256': sha256.convert(data).toString()
    };
    platforms.add({
      'id': entry.key,
      'version': version,
      if (build != null) 'build_number': build,
      'url': 'https://qisw.top/rdesk/dl/$name',
      if (entry.key == 'macos')
        'alternate': {
          'url': 'https://qisw.top/rdesk/dl/RDesk-$version-macos-x64.zip'
        }
    });
  }
  files['RDesk-$version-macos-x64.zip'] = {
    'bytes': data.length,
    'sha256': sha256.convert(data).toString()
  };
  platforms.add({
    'id': 'ios',
    'version': '2.1.0',
    'url': UpdateRelease.storeUri.toString()
  });
  return {'platforms': platforms, 'files': files};
}

UpdateRelease release([List<int> data = const [1, 2, 3]]) =>
    UpdateRelease.fromManifest(
        manifest(data: data), const UpdateTarget('windows'));

class RealHttpOverrides extends HttpOverrides {}

class LocalClient implements HttpClient {
  final HttpClient real =
      HttpOverrides.runWithHttpOverrides(HttpClient.new, RealHttpOverrides());
  final int port;
  LocalClient(this.port);
  @override
  Future<HttpClientRequest> getUrl(Uri uri) => real.getUrl(
      Uri(scheme: 'http', host: '127.0.0.1', port: port, path: uri.path));
  @override
  set connectionTimeout(Duration? value) => real.connectionTimeout = value;
  @override
  void close({bool force = false}) => real.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeService extends AppUpdateService {
  int checks = 0, installs = 0, downloads = 0;
  Completer<File>? downloadResult;
  @override
  Future<File> download(UpdateRelease release, void Function(int) progress) {
    downloads++;
    return downloadResult!.future;
  }

  bool fail = false;
  Completer<UpdateRelease>? pending;
  UpdateRelease found = release();
  @override
  Future<UpdateRelease> check(UpdateTarget target) async {
    checks++;
    if (fail) throw const UpdateFailure('连接失败');
    if (pending != null) return await pending!.future;
    return found;
  }

  @override
  Future<String> openInstaller(UpdateRelease release, File? file) async {
    installs++;
    return 'opened';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('版本按数字比较；同版仅比较已知构建号；拒绝非法版本', () {
    expect(AppVersion.parse('2.10.0').compareTo(AppVersion.parse('2.9.9')),
        greaterThan(0));
    expect(
        AppVersion.parse('2.2.1', 18).compareTo(AppVersion.parse('2.2.1', 17)),
        greaterThan(0));
    expect(
        AppVersion.parse('2.2.1').compareTo(AppVersion.parse('2.2.1', 17)), 0);
    for (final value in [
      'v2.2.1',
      '2.2',
      '2.2.1-beta',
      '../../evil',
      '2.2.1+18'
    ]) {
      expect(() => AppVersion.parse(value), throwsFormatException);
    }
  });
  test('各平台选取正确包，iOS 使用真实商店版本', () {
    expect(
        UpdateRelease.fromManifest(
                manifest(), const UpdateTarget('macos', 'arm64'))
            .filename,
        endsWith('arm64.dmg'));
    expect(
        UpdateRelease.fromManifest(
                manifest(), const UpdateTarget('macos', 'x64'))
            .filename,
        endsWith('x64.zip'));
    expect(
        UpdateRelease.fromManifest(manifest(), const UpdateTarget('android'))
            .filename,
        endsWith('.apk'));
    expect(
        UpdateRelease.fromManifest(manifest(), const UpdateTarget('ios'))
            .version
            .toString(),
        '2.1.0');
  });
  test('拒绝非官网、错平台包、无效摘要、非法大小和重复平台', () {
    for (final url in [
      'http://qisw.top/rdesk/dl/RDesk-2.2.1-windows-x64-setup.exe',
      'https://evil.test/file.exe',
      'https://qisw.top/rdesk/dl/../file.exe',
      'https://qisw.top/rdesk/dl/RDesk-2.2.1-windows-x64-setup.exe?x=1'
    ]) {
      final m = manifest();
      (m['platforms'] as List).first['url'] = url;
      expect(() => UpdateRelease.fromManifest(m, const UpdateTarget('windows')),
          throwsFormatException);
    }
    for (final size in [0, -1, UpdateRelease.maxBytes + 1]) {
      final m = manifest();
      (m['files'] as Map).values.first['bytes'] = size;
      expect(() => UpdateRelease.fromManifest(m, const UpdateTarget('windows')),
          throwsFormatException);
    }
    final m = manifest();
    (m['files'] as Map).values.first['sha256'] = 'bad';
    expect(() => UpdateRelease.fromManifest(m, const UpdateTarget('windows')),
        throwsFormatException);
    final duplicate = manifest();
    (duplicate['platforms'] as List)
        .add((duplicate['platforms'] as List).first);
    expect(
        () => UpdateRelease.fromManifest(
            duplicate, const UpdateTarget('windows')),
        throwsFormatException);
  });

  group('流式下载和校验', () {
    late HttpServer server;
    late Directory temporary;
    late AppUpdateService service;
    late void Function(HttpRequest) respond;
    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      temporary = await Directory.systemTemp.createTemp('rdesk-update-test-');
      service = AppUpdateService(
          clientFactory: () => LocalClient(server.port),
          temporaryDirectory: () async => temporary);
      respond = (r) {
        r.response.add([1, 2, 3]);
        r.response.close();
      };
      server.listen((r) => respond(r));
    });
    tearDown(() async {
      service.dispose();
      await server.close(force: true);
      await temporary.delete(recursive: true);
    });
    test('完整文件通过校验；安装前再次发现文件篡改', () async {
      var bytes = 0;
      final file = await service.download(release(), (n) => bytes = n);
      expect(await file.readAsBytes(), [1, 2, 3]);
      expect(bytes, 3);
      await service.verify(file, release());
      await file.writeAsBytes([3, 2, 1]);
      await expectLater(
          service.verify(file, release()), throwsA(isA<UpdateFailure>()));
    });
    test('截断、超长、摘要错误、HTML、重定向均拒绝且清理文件', () async {
      final cases = <void Function(HttpRequest)>[
        (r) {
          r.response.add([1, 2]);
          r.response.close();
        },
        (r) {
          r.response.add([1, 2, 3, 4]);
          r.response.close();
        },
        (r) {
          r.response.add([3, 2, 1]);
          r.response.close();
        },
        (r) {
          r.response.headers.contentType = ContentType.html;
          r.response.write('bad');
          r.response.close();
        },
        (r) {
          r.response.statusCode = 302;
          r.response.headers.set('location', 'https://evil.test');
          r.response.close();
        },
      ];
      for (final handler in cases) {
        respond = handler;
        await expectLater(
            service.download(release(), (_) {}), throwsA(isA<UpdateFailure>()));
        expect(
            await temporary
                .list(recursive: true)
                .where((e) => e is File)
                .length,
            0);
      }
    });
    test('取消中途下载并拒绝并发下载，不保留半包', () async {
      final started = Completer<void>();
      respond = (r) {
        r.response.add([1]);
        r.response.flush();
        started.complete();
      };
      final download = service.download(release(), (_) {});
      final assertion = expectLater(download, throwsA(isA<UpdateCancelled>()));
      await started.future;
      await expectLater(
          service.download(release(), (_) {}), throwsA(isA<UpdateFailure>()));
      service.cancelDownload();
      await assertion;
      expect(
          await temporary.list(recursive: true).where((e) => e is File).length,
          0);
    });
    test('清单读取成功；过大清单和重定向失败', () async {
      respond = (r) {
        r.response.write(jsonEncode(manifest()));
        r.response.close();
      };
      expect(
          (await service.check(const UpdateTarget('windows')))
              .version
              .toString(),
          '2.2.1');
      respond = (r) {
        r.response.write('x' * 131073);
        r.response.close();
      };
      await expectLater(service.check(const UpdateTarget('windows')),
          throwsA(isA<UpdateFailure>()));
      respond = (r) {
        r.response.statusCode = 302;
        r.response.close();
      };
      await expectLater(service.check(const UpdateTarget('windows')),
          throwsA(isA<UpdateFailure>()));
    });
  });

  group('更新状态', () {
    late FakeService service;
    late AppUpdateProvider provider;
    late DateTime clock;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = FakeService();
      clock = DateTime(2026, 9, 20);
      provider = AppUpdateProvider(
          service: service,
          target: const UpdateTarget('windows'),
          now: () => clock,
          installedVersion: () async => AppVersion.parse('2.2.0', 17));
    });
    tearDown(() => provider.dispose());
    test('自动成功节流六小时，手动检查绕过忽略与节流', () async {
      await provider.check();
      expect(service.checks, 1);
      expect(provider.showBanner, true);
      await provider.ignore();
      expect(provider.showBanner, false);
      await provider.check();
      expect(service.checks, 1);
      await provider.check(manual: true);
      expect(service.checks, 2);
      expect(provider.showBanner, true);
      clock = clock.add(const Duration(hours: 6));
      await provider.check();
      expect(service.checks, 3);
    });
    test('失败节流一小时；关闭自动不影响手动检查', () async {
      service.fail = true;
      await provider.check();
      await provider.check();
      expect(service.checks, 1);
      clock = clock.add(const Duration(hours: 1));
      await provider.check();
      expect(service.checks, 2);
      await provider.setAutomatic(false);
      clock = clock.add(const Duration(days: 1));
      await provider.check();
      expect(service.checks, 2);
      await provider.check(manual: true);
      expect(service.checks, 3);
    });
    test('本地较新 iOS 版本不降级、不提示未发布版', () async {
      service.found =
          UpdateRelease.fromManifest(manifest(), const UpdateTarget('ios'));
      await provider.check();
      expect(provider.phase, UpdatePhase.current);
      expect(provider.release, isNull);
      expect(provider.message, contains('高于商店版本'));
    });
    test('活动会话禁止安装；系统交接不代表安装成功', () async {
      await provider.check();
      await provider.install(sessionActive: true);
      expect(service.installs, 0);
      expect(provider.message, contains('结束远程会话'));
      await provider.install(sessionActive: false);
      expect(service.installs, 1);
      expect(provider.phase, UpdatePhase.handedOff);
      expect(provider.message, contains('按提示'));
    });
    test('下载准备阶段取消不会开始新下载', () async {
      await provider.check();
      final task = provider.download();
      provider.cancelDownload();
      await task;
      expect(service.downloads, 0);
      expect(provider.phase, UpdatePhase.available);
    });
    test('文件交回时取消会删除成品且不能安装', () async {
      await provider.check();
      final dir =
          await Directory.systemTemp.createTemp('update-cancel-return-');
      final file =
          await File('${dir.path}/package.exe').writeAsBytes([1, 2, 3]);
      service.downloadResult = Completer<File>();
      final task = provider.download();
      await Future<void>.delayed(Duration.zero);
      service.downloadResult!.complete(file);
      provider.cancelDownload();
      await task;
      expect(provider.package, isNull);
      expect(await dir.exists(), false);
      expect(provider.phase, UpdatePhase.available);
    });
    test('重启恢复未忽略的新版本提示，仍遵守网络节流', () async {
      await provider.check();
      final next = AppUpdateProvider(
          service: service,
          target: const UpdateTarget('windows'),
          now: () => clock,
          installedVersion: () async => AppVersion.parse('2.2.0', 17));
      await next.check();
      expect(service.checks, 1);
      expect(next.showBanner, true);
      expect(next.release!.version.toString(), '2.2.1');
      next.dispose();
      final upgraded = AppUpdateProvider(
          service: service,
          target: const UpdateTarget('windows'),
          now: () => clock,
          installedVersion: () async => AppVersion.parse('2.2.1', 18));
      await upgraded.check();
      expect(upgraded.showBanner, false);
      upgraded.dispose();
    });

    test('销毁后的迟到结果不通知监听器', () async {
      service.pending = Completer<UpdateRelease>();
      final other = AppUpdateProvider(
          service: service,
          installedVersion: () async => AppVersion.parse('2.2.0'));
      final task = other.check();
      await Future<void>.delayed(Duration.zero);
      other.dispose();
      service.pending!.complete(release());
      await task;
      expect(other.release, isNull);
    });
  });
}
