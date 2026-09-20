import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/wake.dart';
import '../models/wake_pairing.dart';

class WakeApiException implements Exception {
  final String code, message;
  final int statusCode;
  const WakeApiException(this.code, this.message, [this.statusCode = 0]);
  @override
  String toString() => message;
}

class WakeApi {
  final Future<Uri> Function() _baseUri;
  final Future<String?> Function() _accountToken;
  final HttpClient _client;
  WakeApi(
      {required Future<Uri> Function() baseUri,
      required Future<String?> Function() accountToken,
      HttpClient? client})
      : _baseUri = baseUri,
        _accountToken = accountToken,
        _client = client ??
            (HttpClient()..connectionTimeout = const Duration(seconds: 5));

  /// Freeze origin and account for multi-step enrollment/rollback across logout.
  Future<WakeApi> scoped() async {
    final uri = await _baseUri();
    final token = await _accountToken();
    return WakeApi(baseUri: () async => uri, accountToken: () async => token);
  }

  Future<Uri> endpoint() => _baseUri();
  Future<Map<String, dynamic>> _send(String method, String path,
      {Map<String, Object?>? body,
      String? token,
      Map<String, String>? query}) async {
    final base = await _baseUri();
    final loopback = !kReleaseMode &&
        (base.host == '127.0.0.1' ||
            base.host == 'localhost' ||
            base.host == '::1');
    if ((base.scheme != 'https' && !loopback) || base.userInfo.isNotEmpty) {
      throw const WakeApiException('https_required', '远程开机需要有效的 HTTPS 服务器地址');
    }
    final credential = token ?? await _accountToken();
    if (credential == null || credential.isEmpty) {
      throw const WakeApiException('unauthorized', '请先登录账号', 401);
    }
    HttpClientRequest? request;
    try {
      return await (() async {
        request = await _client.openUrl(
            method,
            base.replace(
                path: path, queryParameters: query ?? {}, fragment: ''));
        request!.followRedirects = false;
        request!.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer $credential');
        request!.headers.contentType = ContentType.json;
        if (body != null) request!.write(jsonEncode(body));
        final response = await request!.close();
        final chunks = <int>[];
        await for (final chunk in response) {
          chunks.addAll(chunk);
          if (chunks.length > 262144) {
            throw const WakeApiException('invalid_response', '服务器响应过大');
          }
        }
        Map<String, dynamic> payload = {};
        if (chunks.isNotEmpty) {
          try {
            payload = Map<String, dynamic>.from(
                jsonDecode(utf8.decode(chunks)) as Map);
          } catch (_) {
            if (response.statusCode >= 200 && response.statusCode < 300) {
              throw const WakeApiException('invalid_response', '服务器响应格式不正确');
            }
          }
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final old = response.statusCode == 404 && payload['code'] == null;
          throw WakeApiException(
              old
                  ? 'unsupported'
                  : (payload['code'] as String? ?? 'request_failed'),
              old
                  ? (path.contains('/pairings')
                      ? '服务器需更新扫码配对功能'
                      : '服务器暂不支持远程开机')
                  : (payload['message'] as String? ?? '开机请求失败，请重试'),
              response.statusCode);
        }
        return payload;
      })()
          .timeout(const Duration(seconds: 12));
    } on WakeApiException {
      request?.abort();
      rethrow;
    } on TimeoutException {
      request?.abort();
      throw const WakeApiException('timeout', '请求超时，请检查网络');
    } on IOException {
      request?.abort();
      throw const WakeApiException('network', '无法连接开机服务，请检查网络与证书');
    }
  }

  Future<List<WakeTarget>> targets() async =>
      ((await _send('GET', '/api/wake/targets'))['targets'] as List)
          .map((v) => WakeTarget.fromJson(Map<String, dynamic>.from(v as Map)))
          .toList();
  Future<List<WakeAgent>> agents() async =>
      ((await _send('GET', '/api/wake/agents'))['agents'] as List)
          .map((v) => WakeAgent.fromJson(Map<String, dynamic>.from(v as Map)))
          .toList();
  Future<WakeEnrollment> createAgent(String name) async =>
      WakeEnrollment.fromJson(
          await _send('POST', '/api/wake/agents', body: {'name': name}));
  Future<WakeEnrollment> enableAgent(String id, String name) async =>
      WakeEnrollment.fromJson(await _send(
          'POST', '/api/wake/agents/${Uri.encodeComponent(id)}/enable',
          body: {'name': name}));
  Future<void> stopAgent(String id) async {
    await _send('POST', '/api/wake/agents/${Uri.encodeComponent(id)}/stop',
        body: {});
  }

  Future<void> revokeAgent(String id) async {
    await _send('DELETE', '/api/wake/agents/${Uri.encodeComponent(id)}');
  }

  Future<WakeEnrollment> createTarget(
          {required String name,
          required String deviceId,
          required String mac,
          required String agentId}) async =>
      WakeEnrollment.fromJson(await _send('POST', '/api/wake/targets', body: {
        'name': name,
        'device_id': deviceId,
        'mac': mac,
        'agent_id': agentId
      }));
  Future<void> updateTarget(String id,
      {required String name,
      required String mac,
      required String agentId}) async {
    await _send('PUT', '/api/wake/targets/${Uri.encodeComponent(id)}',
        body: {'name': name, 'mac': mac, 'agent_id': agentId});
  }

  Future<void> deleteTarget(String id) async {
    await _send('DELETE', '/api/wake/targets/${Uri.encodeComponent(id)}');
  }

  Future<WakeEnrollment> rotateTargetToken(String id) async =>
      WakeEnrollment.fromJson(await _send(
          'POST', '/api/wake/targets/${Uri.encodeComponent(id)}/rotate-token',
          body: {}));
  Future<WakeRequest> requestWake(String targetId) async =>
      WakeRequest.fromJson(await _send('POST', '/api/wake/requests',
          body: {'target_id': targetId}));
  Future<WakeRequest> request(String id) async => WakeRequest.fromJson(
      await _send('GET', '/api/wake/requests/${Uri.encodeComponent(id)}'));
  Future<List<WakeRequest>> history(String targetId) async =>
      ((await _send('GET', '/api/wake/requests',
              query: {'target_id': targetId}))['requests'] as List)
          .map((v) => WakeRequest.fromJson(Map<String, dynamic>.from(v as Map)))
          .toList();
  Future<void> targetHeartbeat(String id, String token) async {
    await _send(
        'POST', '/api/wake/targets/${Uri.encodeComponent(id)}/heartbeat',
        token: token, body: {});
  }

  Future<WakePairingSession> createPairing(
          {required String name,
          required String deviceId,
          required String mac}) async =>
      WakePairingSession.fromJson(await _send('POST', '/api/wake/pairings',
          body: {'name': name, 'device_id': deviceId, 'mac': mac}));
  Future<Map<String, dynamic>> resolvePairing(WakePairingCode code) =>
      _send('POST', '/api/wake/pairings/resolve', body: code.resolveBody);
  Future<Map<String, dynamic>> confirmPairing(
          String id, WakePairingCode code) =>
      _send('POST', '/api/wake/pairings/${Uri.encodeComponent(id)}/confirm',
          body: code.confirmBody);
  Future<Map<String, dynamic>> pairingStatus(WakePairingSession s) =>
      _send('POST', '/api/wake/pairings/${Uri.encodeComponent(s.id)}/status',
          body: {'desktop_proof': s.desktopProof});
  Future<String> claimPairing(WakePairingSession s, String token) async =>
      (await _send(
          'POST', '/api/wake/pairings/${Uri.encodeComponent(s.id)}/claim',
          body: {
            'desktop_proof': s.desktopProof,
            'enrollment_token': token
          }))['target_id'] as String;
  Future<void> cancelPairing(WakePairingSession s) async {
    await _send(
        'POST', '/api/wake/pairings/${Uri.encodeComponent(s.id)}/cancel',
        body: {'desktop_proof': s.desktopProof});
  }

  Future<void> cancelPairings() async {
    await _send('POST', '/api/wake/pairings/cancel-all', body: {});
  }

  Future<void> completeTarget(String id, String agentId) async {
    await _send('POST', '/api/wake/targets/${Uri.encodeComponent(id)}/complete',
        body: {'agent_id': agentId, 'bios_confirmed': true});
  }

  void close() => _client.close(force: true);
}
