import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/session.dart';
import '../services/rdesk_bridge_service.dart';

class SessionProvider extends ChangeNotifier {
  final _bridge = RdeskBridgeService.instance;
  SessionInfo? _currentSession;
  Uint8List? _currentFrame;
  int _frameWidth = 0;
  int _frameHeight = 0;
  bool _controlEnabled = true;
  StreamSubscription<RemoteFrameData?>? _frameSubscription;
  Timer? _clipboardSyncTimer;
  bool _autoClipboardSyncEnabled = false;
  bool _clipboardSyncBusy = false;
  String? _lastSyncedClipboard;
  String? _lastAppliedRemoteClipboard;
  String? _sessionPassword;
  bool _isRemoteOnline = true;
  String _connectionStatusLabel = '未连接';
  DateTime? _lastFrameReceivedAt;
  DateTime? _lastReconnectAttemptAt;
  bool _reconnectInFlight = false;
  DateTime? _lastFrameNotifiedAt;
  Timer? _pendingFrameNotify;
  Duration _minFrameInterval = const Duration(milliseconds: 33); // ~30fps cap
  String _qualityPreset = 'auto';
  int _fpsLimit = 30;
  int _jpegQuality = 85;
  bool _isRecording = false;
  bool _privacyScreenOn = false;
  int _currentMonitor = 0;
  List<String> _availableMonitors = ['主显示器'];
  final List<Uint8List> _recordedFrames = [];

  SessionInfo? get currentSession => _currentSession;
  Uint8List? get currentFrame => _currentFrame;
  int get frameWidth => _frameWidth;
  int get frameHeight => _frameHeight;
  bool get controlEnabled => _controlEnabled;
  bool get autoClipboardSyncEnabled => _autoClipboardSyncEnabled;
  bool get isRemoteOnline => _isRemoteOnline;
  String get connectionStatusLabel => _connectionStatusLabel;
  String get qualityPreset => _qualityPreset;
  int get fpsLimit => _fpsLimit;
  int get jpegQuality => _jpegQuality;
  bool get isRecording => _isRecording;
  bool get privacyScreenOn => _privacyScreenOn;
  int get currentMonitor => _currentMonitor;
  List<String> get availableMonitors => List.unmodifiable(_availableMonitors);
  int get recordedFrameCount => _recordedFrames.length;
  bool get isReconnecting =>
      _currentSession?.state == SessionState.reconnecting;
  DateTime? get lastFrameReceivedAt => _lastFrameReceivedAt;

  void setSession(SessionInfo session, {String? accessPassword}) {
    _currentSession = session;
    _sessionPassword = accessPassword;
    _currentFrame = null;
    _frameWidth = 0;
    _frameHeight = 0;
    _isRemoteOnline = true;
    _connectionStatusLabel = '连接中';
    _lastFrameReceivedAt = null;
    _lastReconnectAttemptAt = null;
    _reconnectInFlight = false;
    notifyListeners();
    unawaited(_bindFrameStream(session));
    unawaited(_fetchDisplayList(session.sessionId));
  }

  Future<void> _fetchDisplayList(String sessionId) async {
    try {
      final displays = await _bridge.fetchRemoteDisplays(sessionId);
      if (displays.isNotEmpty) {
        updateAvailableMonitors(displays);
      }
    } catch (_) {}
  }

  void updateFrame(Uint8List frameData, int width, int height) {
    _currentFrame = frameData;
    _frameWidth = width;
    _frameHeight = height;
    notifyListeners();
  }

  void updateLatency(int latencyMs) {
    if (_currentSession != null) {
      _currentSession = _currentSession!.copyWith(latencyMs: latencyMs);
      notifyListeners();
    }
  }

  void toggleControl() {
    _controlEnabled = !_controlEnabled;
    notifyListeners();
  }

  void togglePrivacyScreen() {
    _privacyScreenOn = !_privacyScreenOn;
    if (_currentSession != null) {
      final action = _privacyScreenOn ? 'privacy_on' : 'privacy_off';
      _bridge.sendRemoteAction(_currentSession!.sessionId, action);
    }
    notifyListeners();
  }

  void toggleRecording() {
    _isRecording = !_isRecording;
    if (!_isRecording) {
      _recordedFrames.clear();
    }
    notifyListeners();
  }

  void setMonitor(int index) {
    if (index < 0 || index >= _availableMonitors.length) return;
    _currentMonitor = index;
    if (_currentSession != null) {
      _bridge.sendRemoteAction(
        _currentSession!.sessionId,
        'switch_monitor_$index',
      );
    }
    notifyListeners();
  }

  void updateAvailableMonitors(List<String> monitors) {
    _availableMonitors = monitors.isEmpty ? ['主显示器'] : monitors;
    if (_currentMonitor >= _availableMonitors.length) {
      _currentMonitor = 0;
    }
    notifyListeners();
  }

  void setQualityPreset(String preset, int fps) {
    _qualityPreset = preset;
    _fpsLimit = fps;
    switch (preset) {
      case 'high':
        _jpegQuality = 95;
      case 'medium':
        _jpegQuality = 70;
      case 'low':
        _jpegQuality = 40;
      default:
        _jpegQuality = 85;
    }
    _minFrameInterval = Duration(milliseconds: (1000 / fps).round());
    // Send quality setting to the remote host
    final session = _currentSession;
    if (session != null) {
      _bridge.sendRemoteQuality(session.sessionId, _jpegQuality / 100.0);
    }
    notifyListeners();
  }

  void clearSession() {
    _currentSession = null;
    _sessionPassword = null;
    _currentFrame = null;
    _frameWidth = 0;
    _frameHeight = 0;
    _isRemoteOnline = true;
    _connectionStatusLabel = '未连接';
    _lastFrameReceivedAt = null;
    _lastReconnectAttemptAt = null;
    _reconnectInFlight = false;
    _lastFrameNotifiedAt = null;
    _pendingFrameNotify?.cancel();
    _pendingFrameNotify = null;
    _stopClipboardSync();
    final subscription = _frameSubscription;
    _frameSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    notifyListeners();
  }

  Future<bool> sendTap(
      String sessionId, Offset localPosition, Size viewportSize) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) {
      return Future<bool>.value(false);
    }
    return _bridge.sendRemoteTap(
      sessionId,
      normalizedX: localPosition.dx / viewportSize.width,
      normalizedY: localPosition.dy / viewportSize.height,
    );
  }

  Future<bool> sendNormalizedTap(String sessionId, Offset normalizedPosition) {
    return _bridge.sendRemoteTap(
      sessionId,
      normalizedX: normalizedPosition.dx.clamp(0.0, 1.0),
      normalizedY: normalizedPosition.dy.clamp(0.0, 1.0),
    );
  }

  Future<bool> sendAction(String sessionId, String action) {
    return _bridge.sendRemoteAction(sessionId, action);
  }

  Future<bool> sendLongPress(
      String sessionId, Offset localPosition, Size viewportSize) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) {
      return Future<bool>.value(false);
    }
    return _bridge.sendRemoteLongPress(
      sessionId,
      normalizedX: localPosition.dx / viewportSize.width,
      normalizedY: localPosition.dy / viewportSize.height,
    );
  }

  Future<bool> sendNormalizedLongPress(
    String sessionId,
    Offset normalizedPosition,
  ) {
    return _bridge.sendRemoteLongPress(
      sessionId,
      normalizedX: normalizedPosition.dx.clamp(0.0, 1.0),
      normalizedY: normalizedPosition.dy.clamp(0.0, 1.0),
    );
  }

  Future<bool> sendDrag(
    String sessionId,
    Offset start,
    Offset end,
    Size viewportSize,
  ) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) {
      return Future<bool>.value(false);
    }
    return _bridge.sendRemoteDrag(
      sessionId,
      startX: start.dx / viewportSize.width,
      startY: start.dy / viewportSize.height,
      endX: end.dx / viewportSize.width,
      endY: end.dy / viewportSize.height,
    );
  }

  Future<bool> sendNormalizedDrag(
    String sessionId,
    Offset normalizedStart,
    Offset normalizedEnd,
  ) {
    return _bridge.sendRemoteDrag(
      sessionId,
      startX: normalizedStart.dx.clamp(0.0, 1.0),
      startY: normalizedStart.dy.clamp(0.0, 1.0),
      endX: normalizedEnd.dx.clamp(0.0, 1.0),
      endY: normalizedEnd.dy.clamp(0.0, 1.0),
    );
  }

  Future<bool> sendNormalizedDragPath(
    String sessionId,
    List<Offset> normalizedPoints,
  ) {
    final points = normalizedPoints
        .map((p) => [p.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, 1.0)])
        .toList();
    return _bridge.sendRemoteDragPath(sessionId, points);
  }

  Future<bool> sendTextInput(String sessionId, String text) {
    return _bridge.sendRemoteTextInput(sessionId, text);
  }

  Future<bool> sendClipboard(String sessionId, String text) {
    _lastSyncedClipboard = text;
    return _bridge.sendRemoteClipboard(sessionId, text);
  }

  Future<String?> fetchClipboard(String sessionId) async {
    final text = await _bridge.fetchRemoteClipboard(sessionId);
    if (text != null && text.isNotEmpty) {
      _lastAppliedRemoteClipboard = text;
      _lastSyncedClipboard = text;
    }
    return text;
  }

  Future<void> configureAutoClipboardSync({
    required String sessionId,
    required bool enabled,
  }) async {
    if (_autoClipboardSyncEnabled == enabled &&
        (!enabled || _currentSession?.sessionId == sessionId)) {
      return;
    }

    _autoClipboardSyncEnabled = enabled;
    _stopClipboardSync(notify: false);
    if (!enabled || _currentSession?.sessionId != sessionId) {
      notifyListeners();
      return;
    }

    await _syncClipboard(sessionId);
    _clipboardSyncTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_syncClipboard(sessionId)),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _stopClipboardSync(notify: false);
    _pendingFrameNotify?.cancel();
    unawaited(_frameSubscription?.cancel());
    super.dispose();
  }

  Future<void> _bindFrameStream(SessionInfo session) async {
    await _frameSubscription?.cancel();
    _frameSubscription = _bridge
        .watchSessionFrames(
      session.sessionId,
      peerId: session.peerId,
    )
        .listen((frame) {
      if (_currentSession?.sessionId != session.sessionId) {
        return;
      }
      if (frame == null) {
        _markRemoteUnavailable(session);
        unawaited(_attemptReconnect(session));
        return;
      }

      _currentFrame = frame.bytes;
      _frameWidth = frame.width;
      _frameHeight = frame.height;
      _lastFrameReceivedAt = DateTime.now();
      _reconnectInFlight = false;

      // Update session state (latency / online status) always
      final wasOffline = !_isRemoteOnline;
      _isRemoteOnline = true;
      _connectionStatusLabel = '在线';
      _currentSession = _currentSession?.copyWith(
        latencyMs: frame.latencyMs,
        state: SessionState.active,
      );

      // If we just came back online, notify immediately
      if (wasOffline) {
        _pendingFrameNotify?.cancel();
        _pendingFrameNotify = null;
        _lastFrameNotifiedAt = DateTime.now();
        notifyListeners();
        return;
      }

      // --- Frame rate limiting: cap at ~30fps ---
      final now = DateTime.now();
      final lastNotified = _lastFrameNotifiedAt;
      if (lastNotified != null &&
          now.difference(lastNotified) < _minFrameInterval) {
        // Schedule a deferred notify if not already pending
        _pendingFrameNotify ??= Timer(_minFrameInterval, () {
          _pendingFrameNotify = null;
          _lastFrameNotifiedAt = DateTime.now();
          notifyListeners();
        });
        return;
      }

      _pendingFrameNotify?.cancel();
      _pendingFrameNotify = null;
      _lastFrameNotifiedAt = now;
      notifyListeners();
    });
  }

  void _stopClipboardSync({bool notify = false}) {
    _clipboardSyncTimer?.cancel();
    _clipboardSyncTimer = null;
    _clipboardSyncBusy = false;
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> _syncClipboard(String sessionId) async {
    if (_clipboardSyncBusy || !_autoClipboardSyncEnabled) {
      return;
    }
    if (_currentSession?.sessionId != sessionId) {
      _stopClipboardSync();
      return;
    }

    _clipboardSyncBusy = true;
    try {
      final local = await Clipboard.getData('text/plain');
      final localText = local?.text;
      if (localText != null &&
          localText.isNotEmpty &&
          localText != _lastSyncedClipboard &&
          localText != _lastAppliedRemoteClipboard) {
        final pushed = await _bridge.sendRemoteClipboard(sessionId, localText);
        if (pushed) {
          _lastSyncedClipboard = localText;
        }
      }

      final remoteText = await _bridge.fetchRemoteClipboard(sessionId);
      if (remoteText != null &&
          remoteText.isNotEmpty &&
          remoteText != _lastAppliedRemoteClipboard &&
          remoteText != localText) {
        await Clipboard.setData(ClipboardData(text: remoteText));
        _lastAppliedRemoteClipboard = remoteText;
        _lastSyncedClipboard = remoteText;
      }
    } catch (_) {
      // Keep polling alive on transient clipboard or network errors.
    } finally {
      _clipboardSyncBusy = false;
    }
  }

  void _markRemoteUnavailable(SessionInfo session) {
    final lastFrame = _lastFrameReceivedAt;
    final now = DateTime.now();
    final isDisconnected = lastFrame != null &&
        now.difference(lastFrame) > const Duration(seconds: 10);
    _isRemoteOnline = false;
    _connectionStatusLabel = isDisconnected ? '已离线' : '重连中';
    _currentSession = _currentSession?.copyWith(
      state: isDisconnected
          ? SessionState.disconnected
          : SessionState.reconnecting,
    );
    if (isDisconnected) {
      _currentFrame = null;
      _frameWidth = 0;
      _frameHeight = 0;
    }
    notifyListeners();
  }

  Future<void> _attemptReconnect(SessionInfo session) async {
    // Always check termination first — even when another reconnect is
    // in-flight — so the viewer exits promptly when the host disconnects.
    if (_bridge.isSessionTerminated(session.sessionId)) {
      _connectionStatusLabel = '已被对端断开';
      _currentSession = _currentSession?.copyWith(
        state: SessionState.disconnected,
      );
      _reconnectInFlight = false;
      notifyListeners();
      return;
    }
    if (_reconnectInFlight) {
      return;
    }

    final password = _sessionPassword ?? '';
    final now = DateTime.now();
    if (_lastReconnectAttemptAt != null &&
        now.difference(_lastReconnectAttemptAt!) < const Duration(seconds: 2)) {
      return;
    }

    _reconnectInFlight = true;
    _lastReconnectAttemptAt = now;
    try {
      final resolved = await _bridge.refreshSessionEndpoint(
        session.sessionId,
        deviceId: session.peerId,
        password: password,
      );
      if (_currentSession?.sessionId != session.sessionId) {
        return;
      }
      // Recheck — session may have been terminated while awaiting the server.
      if (_bridge.isSessionTerminated(session.sessionId)) {
        _connectionStatusLabel = '已被对端断开';
        _currentSession = _currentSession?.copyWith(
          state: SessionState.disconnected,
        );
        notifyListeners();
        return;
      }
      if (!resolved.found) {
        _connectionStatusLabel = '设备离线';
        _currentSession = _currentSession?.copyWith(
          state: SessionState.disconnected,
        );
      } else if (!resolved.authorized) {
        _connectionStatusLabel = password.isEmpty ? '等待对端授权' : '密码已变更';
        _currentSession = _currentSession?.copyWith(
          state: SessionState.error,
        );
      } else {
        _connectionStatusLabel = '已重连，等待画面';
        _currentSession = _currentSession?.copyWith(
          state: SessionState.reconnecting,
        );
      }
      notifyListeners();
    } catch (_) {
      if (_currentSession?.sessionId == session.sessionId) {
        _connectionStatusLabel = '重连失败';
        notifyListeners();
      }
    } finally {
      _reconnectInFlight = false;
    }
  }
}
