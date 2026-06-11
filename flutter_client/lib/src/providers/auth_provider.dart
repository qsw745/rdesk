import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import '../services/rdesk_bridge_service.dart';

class AuthProvider extends ChangeNotifier {
  final _bridge = RdeskBridgeService.instance;
  final _secureStorage = const FlutterSecureStorage();
  final _localAuth = LocalAuthentication();

  static const _biometricEnabledKey = 'rdesk.biometric.enabled';
  static const _biometricSessionKey = 'rdesk.biometric.session';
  static const _biometricSessionFallbackKey =
      'rdesk.biometric.session.fallback';
  static const _credentialsKey = 'rdesk.account.credentials';

  Timer? _refreshTimer;

  AccountSession? _session;
  List<AccountDevice> _devices = const [];
  bool _busy = false;
  String? _error;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  bool _hasBiometricSession = false;
  String _biometricLabel = '生物识别';

  AccountSession? get session => _session;
  List<AccountDevice> get devices => List.unmodifiable(_devices);
  bool get isLoggedIn => _session != null;
  bool get busy => _busy;
  String? get error => _error;
  bool get biometricEnabled => _biometricEnabled;
  bool get biometricAvailable => _biometricAvailable;
  bool get canUseBiometricLogin =>
      _biometricEnabled && _biometricAvailable && _hasBiometricSession;
  String get biometricLabel => _biometricLabel;

  Future<void> initialize() async {
    await _loadBiometricPreferences();
    await _refreshBiometricSupport();
    _hasBiometricSession = (await _readBiometricSession()) != null;
    _session = await _bridge.getSavedAccountSession();
    if (_session == null) {
      await _tryAutoRelogin();
    }
    if (_session != null) {
      await refreshDevices(notifyOnStart: false);
      _ensureAutoRefresh();
      if (_biometricEnabled) {
        await _storeBiometricSession(_session!);
      }
    }
    notifyListeners();
  }

  Future<bool> login({
    required String username,
    required String password,
  }) async {
    final ok = await _runAuthAction(() => _bridge.loginAccount(
          username: username,
          password: password,
        ));
    if (ok) {
      await _saveCredentials(username, password);
    }
    return ok;
  }

  Future<bool> register({
    required String username,
    required String password,
    String? displayName,
  }) async {
    final ok = await _runAuthAction(() => _bridge.registerAccount(
          username: username,
          password: password,
          displayName: displayName,
        ));
    if (ok) {
      await _saveCredentials(username, password);
    }
    return ok;
  }

  Future<void> logout() async {
    final existingSession = _session;
    _session = null;
    _devices = const [];
    _error = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    await _bridge.clearSavedAccountSession();
    await _clearCredentials();
    if (!_biometricEnabled) {
      await _clearBiometricSession();
    } else if (existingSession != null) {
      await _storeBiometricSession(existingSession);
    }
    notifyListeners();
  }

  Future<void> refreshDevices({bool notifyOnStart = true}) async {
    if (_session == null) {
      _devices = const [];
      if (notifyOnStart) {
        notifyListeners();
      }
      return;
    }

    _busy = true;
    _error = null;
    if (notifyOnStart) {
      notifyListeners();
    }

    try {
      _devices = await _loadRemoteDevicesOnly();
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      // Auto-re-login when token expires (e.g. server restart)
      if (msg.contains('登录状态已失效')) {
        final relogged = await _tryAutoRelogin();
        if (relogged) {
          try {
            _devices = await _loadRemoteDevicesOnly();
            _error = null;
          } catch (_) {
            _error = msg;
          }
        } else {
          _error = msg;
        }
      } else {
        _error = msg;
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> _runAuthAction(Future<AccountSession> Function() action) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      _session = await action();
      await _bridge.saveAccountSession(_session!);
      _devices = await _loadRemoteDevicesOnly();
      if (_biometricEnabled) {
        await _storeBiometricSession(_session!);
      }
      _ensureAutoRefresh();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<List<AccountDevice>> _loadRemoteDevicesOnly() async {
    final devices = await _bridge.listAccountDevices();
    final localDevice = await _bridge.getLocalDeviceInfo();
    final localId = localDevice.deviceId.trim();
    if (localId.isEmpty) {
      return devices;
    }
    return devices.where((item) => item.deviceId.trim() != localId).toList();
  }

  Future<bool> setBiometricEnabled(bool enabled) async {
    try {
      _error = null;
      if (enabled) {
        if (!_isBiometricPlatform) {
          _error = '当前平台不支持生物识别';
          notifyListeners();
          return false;
        }
        await _refreshBiometricSupport();
        if (!_biometricAvailable) {
          _error = '当前设备未检测到可用的人脸/指纹识别';
          notifyListeners();
          return false;
        }
        if (_session == null) {
          _error = '请先登录账号再开启生物识别登录';
          notifyListeners();
          return false;
        }
        final verified = await _authenticateBiometric(
          reason: '验证身份以开启$_biometricLabel登录',
        );
        if (!verified) {
          _error = '未通过$_biometricLabel验证';
          notifyListeners();
          return false;
        }
        await _storeBiometricSession(_session!);
      } else {
        await _clearBiometricSession();
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_biometricEnabledKey, enabled);
      _biometricEnabled = enabled;
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> loginWithBiometrics() async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      await _refreshBiometricSupport();
      if (!_biometricEnabled) {
        throw Exception('未开启$_biometricLabel登录');
      }
      if (!_biometricAvailable) {
        throw Exception('当前设备不可用$_biometricLabel');
      }

      final verified = await _authenticateBiometric(
        reason: '使用$_biometricLabel登录 RDesk',
      );
      if (!verified) {
        throw Exception('$_biometricLabel验证失败');
      }

      final secureSession = await _readBiometricSession();
      if (secureSession == null) {
        throw Exception('未找到可用的生物识别登录凭据，请先账号登录一次');
      }

      _session = secureSession;
      await _bridge.saveAccountSession(secureSession);
      _devices = await _loadRemoteDevicesOnly();
      _ensureAutoRefresh();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _loadBiometricPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _biometricEnabled = prefs.getBool(_biometricEnabledKey) ?? false;
  }

  Future<void> _refreshBiometricSupport() async {
    if (!_isBiometricPlatform) {
      _biometricAvailable = false;
      _biometricLabel = '生物识别';
      return;
    }
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      final types = await _localAuth.getAvailableBiometrics();
      _biometricAvailable = supported && canCheck && types.isNotEmpty;

      if (types.contains(BiometricType.face)) {
        _biometricLabel = Platform.isIOS ? 'Face ID' : '面容识别';
      } else if (types.contains(BiometricType.fingerprint)) {
        _biometricLabel = Platform.isMacOS ? 'Touch ID' : '指纹识别';
      } else {
        _biometricLabel = '生物识别';
      }
    } catch (_) {
      _biometricAvailable = false;
      _biometricLabel = '生物识别';
    }
  }

  Future<bool> _authenticateBiometric({required String reason}) async {
    if (!_isBiometricPlatform) {
      return false;
    }
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _storeBiometricSession(AccountSession session) async {
    final payload = jsonEncode(<String, String>{
      'token': session.token,
      'user_id': session.userId,
      'username': session.username,
      'display_name': session.displayName,
    });
    try {
      await _secureStorage.write(key: _biometricSessionKey, value: payload);
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_biometricSessionFallbackKey, payload);
    }
    _hasBiometricSession = true;
  }

  Future<AccountSession?> _readBiometricSession() async {
    try {
      var raw = await _secureStorage.read(key: _biometricSessionKey);
      if (raw == null || raw.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        raw = prefs.getString(_biometricSessionFallbackKey);
      }
      if (raw == null || raw.isEmpty) {
        return null;
      }
      final payload = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final token = payload['token'] as String? ?? '';
      final userId = payload['user_id'] as String? ?? '';
      final username = payload['username'] as String? ?? '';
      final displayName = payload['display_name'] as String? ?? username;
      if (token.isEmpty || userId.isEmpty || username.isEmpty) {
        return null;
      }
      return AccountSession(
        token: token,
        userId: userId,
        username: username,
        displayName: displayName,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearBiometricSession() async {
    await _secureStorage.delete(key: _biometricSessionKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_biometricSessionFallbackKey);
    _hasBiometricSession = false;
  }

  bool get _isBiometricPlatform {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isMacOS;
  }

  Future<void> _saveCredentials(String username, String password) async {
    try {
      final payload = jsonEncode({'u': username, 'p': password});
      await _secureStorage.write(key: _credentialsKey, value: payload);
    } catch (_) {}
  }

  Future<void> _clearCredentials() async {
    try {
      await _secureStorage.delete(key: _credentialsKey);
    } catch (_) {}
  }

  Future<bool> _tryAutoRelogin() async {
    try {
      final raw = await _secureStorage.read(key: _credentialsKey);
      if (raw == null || raw.isEmpty) return false;
      final cred = jsonDecode(raw) as Map<String, dynamic>;
      final username = cred['u'] as String?;
      final password = cred['p'] as String?;
      if (username == null || password == null) return false;
      _session = await _bridge.loginAccount(
        username: username,
        password: password,
      );
      await _bridge.saveAccountSession(_session!);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _ensureAutoRefresh() {
    _refreshTimer?.cancel();
    if (_session == null) {
      _refreshTimer = null;
      return;
    }
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_session != null && !_busy) {
        refreshDevices(notifyOnStart: false);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    super.dispose();
  }
}
