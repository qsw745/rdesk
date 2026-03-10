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
  int? _lastFrameIdentity;
  DateTime? _lastFrameNotifiedAt;
  Timer? _pendingFrameNotify;
  static const _minFrameInterval = Duration(milliseconds: 33); // ~30fps cap

  SessionInfo? get currentSession => _currentSession;
  Uint8List? get currentFrame => _currentFrame;
  int get frameWidth => _frameWidth;
  int get frameHeight => _frameHeight;
  bool get controlEnabled => _controlEnabled;
  bool get autoClipboardSyncEnabled => _autoClipboardSyncEnabled;
  bool get isRemoteOnline => _isRemoteOnline;
  String get connectionStatusLabel => _connectionStatusLabel;
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
    _lastFrameIdentity = null;
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

      // --- Frame deduplication: skip notification if identical frame ---
      final frameId = identityHashCode(frame.bytes);
      final isDuplicate = frameId == _lastFrameIdentity &&
          frame.width == _frameWidth &&
          frame.height == _frameHeight;

      _currentFrame = frame.bytes;
      _frameWidth = frame.width;
      _frameHeight = frame.height;
      _lastFrameReceivedAt = DateTime.now();
      _reconnectInFlight = false;
      _lastFrameIdentity = frameId;

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

      // If duplicate frame, skip notification entirely
      if (isDuplicate) return;

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
    notifyListeners();
  }

  Future<void> _attemptReconnect(SessionInfo session) async {
    if (_reconnectInFlight) {
      return;
    }
    if (_bridge.isSessionTerminated(session.sessionId)) {
      _connectionStatusLabel = '已被对端断开';
      _currentSession = _currentSession?.copyWith(
        state: SessionState.disconnected,
      );
      notifyListeners();
      return;
    }

    final password = _sessionPassword;
    if (password == null || password.isEmpty) {
      return;
    }
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
      if (!resolved.found) {
        _connectionStatusLabel = '设备离线';
        _currentSession = _currentSession?.copyWith(
          state: SessionState.disconnected,
        );
      } else if (!resolved.authorized) {
        _connectionStatusLabel = '密码已变更';
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
