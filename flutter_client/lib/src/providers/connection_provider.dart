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
  String? _pendingQuickConnectPeerId;

  DeviceInfo? get localDevice => _localDevice;
  String get temporaryPassword => _temporaryPassword;
  SessionState get connectionState => _connectionState;
  String? get errorMessage => _errorMessage;
  List<ConnectionRecord> get recentConnections =>
      List.unmodifiable(_recentConnections);
  String? get pendingQuickConnectPeerId => _pendingQuickConnectPeerId;

  Future<void> initialize() async {
    try {
      _localDevice = await _bridge.getLocalDeviceInfo();
      _temporaryPassword = await _bridge.getTemporaryPassword();
      _recentConnections = await _bridge.listConnectionHistory();
      _errorMessage = null;
    } catch (e) {
      _connectionState = SessionState.error;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    }
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
      await _bridge.touchTrustedPeer(deviceId);
      _connectionState = SessionState.active;
      _recentConnections = await _bridge.listConnectionHistory();
      notifyListeners();
      return sessionId;
    } catch (e) {
      _connectionState = SessionState.error;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      await _bridge.recordConnectionFailure(
        peerId: deviceId,
        failureReason: _errorMessage!,
      );
      _recentConnections = await _bridge.listConnectionHistory();
      notifyListeners();
      return null;
    }
  }

  Future<void> disconnect(String sessionId) async {
    await _bridge.disconnect(sessionId);
    _connectionState = SessionState.idle;
    notifyListeners();
  }

  void prepareQuickConnect(String peerId) {
    _pendingQuickConnectPeerId = peerId;
    notifyListeners();
  }

  String? consumeQuickConnectPeerId() {
    final peerId = _pendingQuickConnectPeerId;
    _pendingQuickConnectPeerId = null;
    return peerId;
  }

  Future<String?> getTrustedPassword(String peerId) {
    return _bridge.getTrustedPeerPassword(peerId);
  }

  Future<DeviceInfo?> getLocalDevice() async {
    return _localDevice ?? await _bridge.getLocalDeviceInfo();
  }
}
