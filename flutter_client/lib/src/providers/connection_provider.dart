import 'package:flutter/foundation.dart';
import '../models/device.dart';
import '../models/connection_info.dart';
import '../models/session.dart';
import '../services/rdesk_bridge_service.dart';

class ConnectionProvider extends ChangeNotifier {
  final _bridge = RdeskBridgeService.instance;
  DeviceInfo? _localDevice;
  String _temporaryPassword = '';
  SessionState _connectionState = SessionState.idle;
  String? _errorMessage;
  List<ConnectionRecord> _recentConnections = [];

  DeviceInfo? get localDevice => _localDevice;
  String get temporaryPassword => _temporaryPassword;
  SessionState get connectionState => _connectionState;
  String? get errorMessage => _errorMessage;
  List<ConnectionRecord> get recentConnections => List.unmodifiable(_recentConnections);

  Future<void> initialize() async {
    _localDevice = await _bridge.getLocalDeviceInfo();
    _temporaryPassword = await _bridge.getTemporaryPassword();
    _recentConnections = await _bridge.listConnectionHistory();
    notifyListeners();
  }

  Future<void> refreshPassword() async {
    _temporaryPassword = await _bridge.generateTemporaryPassword();
    notifyListeners();
  }

  Future<String?> connect(String deviceId, String password) async {
    _connectionState = SessionState.connecting;
    _errorMessage = null;
    notifyListeners();

    try {
      final sessionId = await _bridge.connectToPeer(deviceId, password);
      _connectionState = SessionState.active;
      _recentConnections = await _bridge.listConnectionHistory();
      notifyListeners();
      return sessionId;
    } catch (e) {
      _connectionState = SessionState.error;
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> disconnect(String sessionId) async {
    await _bridge.disconnect(sessionId);
    _connectionState = SessionState.idle;
    notifyListeners();
  }
}
