import 'package:flutter/foundation.dart';

import '../models/account.dart';
import '../services/rdesk_bridge_service.dart';

class AuthProvider extends ChangeNotifier {
  final _bridge = RdeskBridgeService.instance;

  AccountSession? _session;
  List<AccountDevice> _devices = const [];
  bool _busy = false;
  String? _error;

  AccountSession? get session => _session;
  List<AccountDevice> get devices => List.unmodifiable(_devices);
  bool get isLoggedIn => _session != null;
  bool get busy => _busy;
  String? get error => _error;

  Future<void> initialize() async {
    _session = await _bridge.getSavedAccountSession();
    if (_session != null) {
      await refreshDevices(notifyOnStart: false);
    }
    notifyListeners();
  }

  Future<bool> login({
    required String username,
    required String password,
  }) {
    return _runAuthAction(() => _bridge.loginAccount(
          username: username,
          password: password,
        ));
  }

  Future<bool> register({
    required String username,
    required String password,
    String? displayName,
  }) {
    return _runAuthAction(() => _bridge.registerAccount(
          username: username,
          password: password,
          displayName: displayName,
        ));
  }

  Future<void> logout() async {
    _session = null;
    _devices = const [];
    _error = null;
    await _bridge.clearSavedAccountSession();
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
      _devices = await _bridge.listAccountDevices();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
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
      _devices = await _bridge.listAccountDevices();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
