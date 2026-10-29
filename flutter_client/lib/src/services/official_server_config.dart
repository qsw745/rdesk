import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

/// 普通版的服务器来自随应用交付的配置，用户偏好不能改变信任来源。
class OfficialServerConfig {
  static const _storage = FlutterSecureStorage();
  static const _policyOriginKey = 'rdesk.server_policy_origin';
  static const accountServerKey = 'rdesk.account_server';
  static const credentialsKey = 'rdesk.account.credentials';
  static const biometricSessionKey = 'rdesk.biometric.session';
  static const biometricFallbackKey = 'rdesk.biometric.session.fallback';
  static const trustedPasswordPrefix = 'rdesk.trusted_peers.pw.';
  static const _signalingKey = 'rdesk.signaling_server';
  static const _relayKey = 'rdesk.relay_server';
  // 只有这个历史官方来源允许接收尚未绑定来源的旧版凭据。
  static const _legacyAccountOrigin = 'https://qisw.top';
  static Future<void>? _migration;
  static bool _mustReload = false;

  static Uri get apiBase {
    final uri = Uri.parse(AppConstants.defaultSignalingServer);
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError('官方服务器必须配置为有效的 HTTPS 来源');
    }
    return uri;
  }

  static void requireOfficial(Uri uri) {
    if (uri.origin != apiBase.origin || uri.userInfo.isNotEmpty) {
      throw StateError('账号请求只能发送到官方 HTTPS 服务');
    }
  }

  // 仅用于识别升级前的账号来源，绝不作为请求目标。
  static const _legacyOfficialAddresses = {
    'https://qisw.top',
    'http://qisw.top',
    'qisw.top',
    'qisw.top:80',
    'qisw.top:21116',
    'http://qisw.top:80',
    'http://qisw.top:21116',
    'https://rdesk.qisw.top',
    'http://rdesk.qisw.top',
    'rdesk.qisw.top',
    '101.37.21.147',
    '101.37.21.147:80',
    '101.37.21.147:21116',
    'http://101.37.21.147',
    'http://101.37.21.147:80',
    'http://101.37.21.147:21116',
    '124.223.200.182',
    '124.223.200.182:80',
    '124.223.200.182:21116',
    'http://124.223.200.182',
    'http://124.223.200.182:80',
    'http://124.223.200.182:21116',
    'qswnotes.com',
    'qswnotes.com:80',
    'qswnotes.com:21116',
    'http://qswnotes.com',
    'http://qswnotes.com:80',
    'http://qswnotes.com:21116',
    'https://qswnotes.com',
    'https://qswnotes.com:21116',
  };

  /// 并发启动路径共用同一迁移；失败不标记完成，下次重试仍按旧来源处理。
  static Future<void> prepare() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = _migration;
    if (pending != null) return pending;
    // setString 会先更新 Dart 缓存，再等待原生写入；标记命中不能绕过在途迁移。
    if (!_mustReload && prefs.getString(_policyOriginKey) == apiBase.origin) {
      return;
    }
    final migration = _runMigration(prefs);
    _migration = migration;
    try {
      await migration;
    } finally {
      _migration = null;
    }
  }

  static Future<void> _runMigration(SharedPreferences prefs) async {
    try {
      if (_mustReload) await prefs.reload();
      await _migrate(prefs);
      _mustReload = false;
    } catch (_) {
      // 不能信任失败写操作留下的内存缓存；重试前必须重新读取持久数据。
      _mustReload = true;
      rethrow;
    }
  }

  static Future<void> _persist(Future<bool> write) async {
    if (!await write) throw StateError('无法保存服务器安全配置，请稍后重试');
  }

  static Future<void> _migrate(SharedPreferences prefs) async {
    final origin = apiBase.origin;
    final priorOrigin = prefs.getString(_policyOriginKey);
    final priorAccount = prefs.getString(accountServerKey);
    final legacy = prefs
        .getString(_signalingKey)
        ?.trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'/+$'), '');
    final legacyIsOfficial = legacy == null ||
        legacy.isEmpty ||
        legacy == origin ||
        _legacyOfficialAddresses.contains(legacy);
    final knownOrigin = priorOrigin == origin ||
        (priorOrigin == null && origin == _legacyAccountOrigin);
    final keepAccount = knownOrigin &&
        (priorAccount == null || priorAccount == origin) &&
        legacyIsOfficial;

    // 元数据可能已被清空，必须同时处理安全存储中没有列表记录的孤儿密码。
    final secrets = await _storage.readAll();
    for (final entry in secrets.entries) {
      if (!entry.key.startsWith(trustedPasswordPrefix)) continue;
      if (keepAccount) {
        final scoped = _scopeTrustedPassword(entry.value, origin);
        if (scoped != null) {
          await _storage.write(key: entry.key, value: scoped);
          continue;
        }
      }
      await _storage.delete(key: entry.key);
    }

    if (keepAccount) {
      await _bindLegacySecurePayload(credentialsKey, origin);
      await _bindLegacySecurePayload(biometricSessionKey, origin);
      final fallback = prefs.getString(biometricFallbackKey);
      if (fallback != null) {
        final scoped = _scopedPayload(fallback, origin);
        if (scoped == null) {
          await _persist(prefs.remove(biometricFallbackKey));
        } else {
          await _persist(prefs.setString(biometricFallbackKey, scoped));
        }
      }
      if (prefs.containsKey('rdesk.account_token')) {
        await _persist(prefs.setString(accountServerKey, origin));
      }
    } else {
      // 必须全部成功才删除旧地址；中断后仍能判断旧凭据不可信。
      await _storage.delete(key: credentialsKey);
      await _storage.delete(key: biometricSessionKey);
      for (final key in [
        'rdesk.account_token',
        'rdesk.account_user_id',
        'rdesk.account_username',
        'rdesk.account_display_name',
        accountServerKey,
        biometricFallbackKey,
        'rdesk.biometric.enabled',
        'rdesk.trusted_peers',
        'rdesk.trusted_incoming_viewers',
      ]) {
        await _persist(prefs.remove(key));
      }
    }
    await _persist(prefs.remove(_signalingKey));
    await _persist(prefs.remove(_relayKey));
    // 新版本更换官方域名也走本流程，不将旧站的账号凭据带到新站。
    await _persist(prefs.setString(_policyOriginKey, origin));
  }

  static Future<void> _bindLegacySecurePayload(
      String key, String origin) async {
    final raw = await _storage.read(key: key);
    if (raw == null) return;
    final scoped = _scopedPayload(raw, origin);
    if (scoped == null) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: scoped);
    }
  }

  static String? _scopedPayload(String raw, String origin) {
    try {
      final payload = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (payload['server'] != null && payload['server'] != origin) return null;
      payload['server'] = origin;
      return jsonEncode(payload);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  static String? _scopeTrustedPassword(String raw, String origin) {
    // 已绑定过来源的密码不能被重新标记为当前来源。
    try {
      final payload = jsonDecode(raw);
      if (payload is Map && payload.containsKey('server')) {
        if (payload['server'] != origin || payload['password'] is! String) {
          return null;
        }
        return raw;
      }
    } on FormatException {
      // 最早版本以原字符串存储密码，只有已确认的历史官方来源能迁入。
    }
    return jsonEncode({'server': origin, 'password': raw});
  }
}
