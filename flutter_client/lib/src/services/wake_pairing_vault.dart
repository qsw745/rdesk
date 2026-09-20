import 'dart:convert';
import '../models/wake.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class WakePairingVault {
  Future<WakeEnrollment?> enrollment(String user, Uri endpoint) async => null;
  Future<Map<String, dynamic>?> read(String user, Uri endpoint);
  Future<void> save(String user, Uri endpoint, Map<String, Object?> data);
  Future<void> promote(String user, Uri endpoint, String id, String token);
  Future<void> clear(String user, Uri endpoint);
}

class SecureWakePairingVault implements WakePairingVault {
  final FlutterSecureStorage storage;
  const SecureWakePairingVault(this.storage);
  String _suffix(String user, Uri endpoint) =>
      '${sha256.convert(utf8.encode('$endpoint|$user'))}';
  String _key(String user, Uri endpoint) =>
      'rdesk.wake.pairing.${_suffix(user, endpoint)}';
  @override
  Future<WakeEnrollment?> enrollment(String user, Uri endpoint) async {
    final value = await storage.read(
        key: 'rdesk.wake.windows.${_suffix(user, endpoint)}');
    return value == null
        ? null
        : WakeEnrollment.fromJson(jsonDecode(value) as Map<String, dynamic>);
  }

  @override
  Future<Map<String, dynamic>?> read(String user, Uri endpoint) async {
    final value = await storage.read(key: _key(user, endpoint));
    return value == null ? null : jsonDecode(value) as Map<String, dynamic>;
  }

  @override
  Future<void> save(String user, Uri endpoint, Map<String, Object?> data) =>
      storage.write(key: _key(user, endpoint), value: jsonEncode(data));
  @override
  Future<void> promote(String user, Uri endpoint, String id, String token) =>
      storage.write(
          key: 'rdesk.wake.windows.${_suffix(user, endpoint)}',
          value: jsonEncode({'id': id, 'token': token}));
  @override
  Future<void> clear(String user, Uri endpoint) =>
      storage.delete(key: _key(user, endpoint));
}
