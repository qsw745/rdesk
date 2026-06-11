import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/trusted_peer.dart';
import '../services/rdesk_bridge_service.dart';
import '../utils/constants.dart';

class SettingsProvider extends ChangeNotifier {
  final _bridge = RdeskBridgeService.instance;
  String _signalingServer = AppConstants.defaultSignalingServer;
  String _relayServer = AppConstants.defaultRelayServer;
  bool _autoAccept = false;
  bool _autoClipboardSync = false;
  bool _rememberTrustedPeers = true;
  String _theme = 'system';
  String? _permanentPassword;
  List<TrustedPeer> _trustedPeers = [];
  List<TrustedPeer> _trustedIncomingViewers = [];
  bool _lockAfterDisconnect = false;
  bool _unattendedMode = false;

  String get signalingServer => _signalingServer;
  String get relayServer => _relayServer;
  bool get autoAccept => _autoAccept;
  bool get autoClipboardSync => _autoClipboardSync;
  bool get rememberTrustedPeers => _rememberTrustedPeers;
  String get theme => _theme;
  String? get permanentPassword => _permanentPassword;
  List<TrustedPeer> get trustedPeers => List.unmodifiable(_trustedPeers);
  List<TrustedPeer> get trustedIncomingViewers =>
      List.unmodifiable(_trustedIncomingViewers);
  bool get lockAfterDisconnect => _lockAfterDisconnect;
  bool get unattendedMode => _unattendedMode;

  Future<void> loadSettings() async {
    try {
      final settings = await _bridge.loadSettings();
      _signalingServer = settings.signalingServer;
      _relayServer = settings.relayServer;
      _autoAccept = settings.autoAccept;
      _autoClipboardSync = settings.autoClipboardSync;
      _rememberTrustedPeers = settings.rememberTrustedPeers;
      _theme = settings.theme;
      _permanentPassword = settings.permanentPassword;
      _trustedPeers = await _bridge.listTrustedPeers();
      _trustedIncomingViewers = await _bridge.listTrustedIncomingViewers();
    } catch (_) {
      _trustedPeers = [];
      _trustedIncomingViewers = [];
    }
    // Load local-only settings
    try {
      final prefs = await SharedPreferences.getInstance();
      _lockAfterDisconnect =
          prefs.getBool('rdesk.lock_after_disconnect') ?? false;
      _unattendedMode = prefs.getBool('rdesk.unattended_mode') ?? false;
    } catch (_) {}
    notifyListeners();
  }

  Future<void> updateSignalingServer(String server) async {
    _signalingServer = server;
    await _bridge.saveSettings(signalingServer: server);
    notifyListeners();
  }

  Future<void> updateRelayServer(String server) async {
    _relayServer = server;
    await _bridge.saveSettings(relayServer: server);
    notifyListeners();
  }

  Future<void> setAutoAccept(bool value) async {
    _autoAccept = value;
    await _bridge.saveSettings(autoAccept: value);
    if (!value) {
      await _bridge.clearTrustedIncomingViewers();
      _trustedIncomingViewers = [];
    }
    notifyListeners();
  }

  Future<void> setAutoClipboardSync(bool value) async {
    _autoClipboardSync = value;
    await _bridge.saveSettings(autoClipboardSync: value);
    notifyListeners();
  }

  Future<void> setRememberTrustedPeers(bool value) async {
    _rememberTrustedPeers = value;
    await _bridge.saveSettings(rememberTrustedPeers: value);
    if (!value) {
      await _bridge.clearTrustedPeers();
      _trustedPeers = [];
    }
    notifyListeners();
  }

  Future<void> setTheme(String theme) async {
    _theme = theme;
    await _bridge.saveSettings(theme: theme);
    notifyListeners();
  }

  Future<void> setPermanentPassword(String? password) async {
    _permanentPassword = password;
    await _bridge.setPermanentPassword(password);
    notifyListeners();
  }

  Future<void> setLockAfterDisconnect(bool value) async {
    _lockAfterDisconnect = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('rdesk.lock_after_disconnect', value);
    notifyListeners();
  }

  Future<void> setUnattendedMode(bool value) async {
    _unattendedMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('rdesk.unattended_mode', value);
    notifyListeners();
  }

  Future<void> refreshTrustedPeers() async {
    _trustedPeers = await _bridge.listTrustedPeers();
    _trustedIncomingViewers = await _bridge.listTrustedIncomingViewers();
    notifyListeners();
  }

  Future<void> removeTrustedPeer(String deviceId) async {
    await _bridge.removeTrustedPeer(deviceId);
    await refreshTrustedPeers();
  }

  Future<void> clearTrustedPeers() async {
    await _bridge.clearTrustedPeers();
    _trustedPeers = [];
    notifyListeners();
  }

  Future<void> removeTrustedIncomingViewer(String deviceId) async {
    await _bridge.removeTrustedIncomingViewer(deviceId);
    await refreshTrustedPeers();
  }

  Future<void> clearTrustedIncomingViewers() async {
    await _bridge.clearTrustedIncomingViewers();
    _trustedIncomingViewers = [];
    notifyListeners();
  }
}
