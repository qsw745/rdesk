import 'package:flutter/foundation.dart';
import '../services/rdesk_bridge_service.dart';

class SettingsProvider extends ChangeNotifier {
  final _bridge = RdeskBridgeService.instance;
  String _signalingServer = 'rs.rdesk.com:21116';
  String _relayServer = 'rs.rdesk.com:21117';
  bool _autoAccept = false;
  String _theme = 'system';
  String? _permanentPassword;

  String get signalingServer => _signalingServer;
  String get relayServer => _relayServer;
  bool get autoAccept => _autoAccept;
  String get theme => _theme;
  String? get permanentPassword => _permanentPassword;

  Future<void> loadSettings() async {
    final settings = await _bridge.loadSettings();
    _signalingServer = settings.signalingServer;
    _relayServer = settings.relayServer;
    _autoAccept = settings.autoAccept;
    _theme = settings.theme;
    _permanentPassword = settings.permanentPassword;
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
}
