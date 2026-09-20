import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_update.dart';

class UpdateFailure implements Exception {
  final String message;
  const UpdateFailure(this.message);
  @override
  String toString() => message;
}

class UpdateCancelled extends UpdateFailure {
  const UpdateCancelled() : super('下载已取消');
}

/// An isolated HTTP client: never inherits relay URLs, credentials or redirects.
class AppUpdateService {
  static final feed = Uri.parse('https://qisw.top/rdesk/releases.json');
  static const channel = MethodChannel('com.qsw.rdesk/app_update');
  final HttpClient Function() clientFactory;
  final Future<Directory> Function() temporaryDirectory;
  HttpClient? _downloadClient;
  HttpClient? _checkClient;
  int _generation = 0;
  AppUpdateService(
      {HttpClient Function()? clientFactory,
      Future<Directory> Function()? temporaryDirectory})
      : clientFactory = clientFactory ?? HttpClient.new,
        temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  Future<HttpClientResponse> _get(HttpClient client, Uri uri) async {
    client.connectionTimeout = const Duration(seconds: 10);
    final request =
        await client.getUrl(uri).timeout(const Duration(seconds: 15));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw const UpdateFailure('更新服务暂不可用，请稍后重试');
    if (response.headers.contentType?.mimeType == 'text/html') {
      throw const UpdateFailure('更新服务返回了无效内容');
    }
    return response;
  }

  Future<UpdateRelease> check(UpdateTarget target) async {
    final client = clientFactory();
    _checkClient?.close(force: true);
    _checkClient = client;
    try {
      return await (() async {
        final response = await _get(client, feed);
        const limit = 128 * 1024;
        if (response.contentLength > limit) throw const UpdateFailure('更新清单过大');
        final data = <int>[];
        await for (final chunk
            in response.timeout(const Duration(seconds: 15))) {
          if (data.length + chunk.length > limit)
            throw const UpdateFailure('更新清单过大');
          data.addAll(chunk);
        }
        return UpdateRelease.fromManifest(
            jsonDecode(utf8.decode(data)) as Map<String, dynamic>, target);
      })()
          .timeout(const Duration(seconds: 30));
    } finally {
      client.close(force: true);
      if (identical(_checkClient, client)) _checkClient = null;
    }
  }

  void cancelDownload() {
    _generation++;
    _downloadClient?.close(force: true);
  }

  void dispose() {
    cancelDownload();
    _checkClient?.close(force: true);
  }

  Future<File> download(
      UpdateRelease release, void Function(int) progress) async {
    if (_downloadClient != null) throw const UpdateFailure('已有下载正在进行');
    if (release.isStore) throw const UpdateFailure('请通过 App Store 更新');
    final generation = ++_generation;
    final client = clientFactory();
    _downloadClient = client;
    Directory? directory;
    RandomAccessFile? writer;
    var complete = false;
    try {
      final root =
          Directory('${(await temporaryDirectory()).path}/rdesk-updates');
      await root.create(recursive: true);
      directory = await root.createTemp('download-');
      final partial = File('${directory.path}/${release.filename}.part');
      writer = await partial.open(mode: FileMode.write);
      final response = await _get(client, release.uri);
      if (response.contentLength != -1 &&
          response.contentLength != release.bytes) {
        throw const UpdateFailure('安装包大小不匹配，请重新检查更新');
      }
      final digest = _DigestSink();
      final hash = sha256.startChunkedConversion(digest);
      var received = 0;
      await (() async {
        await for (final chunk
            in response.timeout(const Duration(seconds: 30))) {
          if (generation != _generation) throw const UpdateCancelled();
          received += chunk.length;
          if (received > release.bytes! || received > UpdateRelease.maxBytes) {
            throw const UpdateFailure('安装包大小超出预期');
          }
          hash.add(chunk);
          await writer!.writeFrom(chunk);
          progress(received);
        }
      })()
          .timeout(const Duration(minutes: 20));
      hash.close();
      await writer.close();
      writer = null;
      if (generation != _generation) throw const UpdateCancelled();
      if (received != release.bytes ||
          digest.value.toString() != release.sha256) {
        throw const UpdateFailure('安装包校验失败，请重新下载');
      }
      final result =
          await partial.rename('${directory.path}/${release.filename}');
      if (generation != _generation) throw const UpdateCancelled();
      complete = true;
      return result;
    } catch (_) {
      if (generation != _generation) throw const UpdateCancelled();
      rethrow;
    } finally {
      await writer?.close();
      client.close(force: true);
      _downloadClient = null;
      if (!complete && directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }

  Future<void> verify(File file, UpdateRelease release) async {
    if (!await file.exists() ||
        await file.length() != release.bytes ||
        (await sha256.bind(file.openRead()).first).toString() !=
            release.sha256) {
      throw const UpdateFailure('安装包已损坏或被移除，请重新下载');
    }
  }

  /// Returns only installer hand-off status, never claims installation succeeded.
  Future<String> openInstaller(UpdateRelease release, File? file) async {
    if (release.isStore) {
      if (!await launchUrl(UpdateRelease.storeUri,
          mode: LaunchMode.externalApplication)) {
        throw const UpdateFailure('无法打开 App Store，请稍后重试');
      }
      return 'store';
    }
    if (file == null) throw const UpdateFailure('请先下载安装包');
    await verify(file, release);
    if (Platform.isAndroid) {
      return await channel.invokeMethod<String>('install', {
            'path': file.path,
            'sha256': release.sha256,
            'bytes': release.bytes,
          }) ??
          'failed';
    }
    if (Platform.isWindows) {
      await Process.start(file.path, [], mode: ProcessStartMode.detached);
    } else if (Platform.isMacOS) {
      final result = await Process.run('/usr/bin/open', [file.path]);
      if (result.exitCode != 0) throw const UpdateFailure('无法打开安装包，请重新下载');
    } else {
      throw const UpdateFailure('此平台暂不支持安装更新');
    }
    return 'opened';
  }

  Future<void> openInstallSettings() =>
      channel.invokeMethod('openInstallSettings');
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
