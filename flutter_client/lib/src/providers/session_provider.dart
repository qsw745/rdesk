import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import '../models/session.dart';
import '../services/rdesk_bridge_service.dart';
import '../utils/canvas_rotation.dart';

class SessionProvider extends ChangeNotifier with WidgetsBindingObserver {
  SessionProvider() {
    WidgetsBinding.instance.addObserver(this);
  }

  /// 判定远端离线前允许的无帧时长。
  ///
  /// 必须显著大于被控端的保活重传间隔（Android 侧为 5 秒），否则网络稍有
  /// 抖动就会误判掉线；此前该值与保活间隔同为 10 秒，余量为零。
  static const _offlineGracePeriod = Duration(seconds: 30);

  /// 连续多少次重连尝试失败后，才认定连接真的救不回来。
  ///
  /// 单次失败几乎总是网络抖动：切应用、切 Wi-Fi、锁屏后系统冻结网络，都会让
  /// 一次请求抛异常。此前一次异常就写下终态标签「重连失败」，界面随即把用户
  /// 踢回设备列表——这正是「切个应用回来就断开」的直接成因。
  static const _reconnectFailureThreshold = 4;

  /// 连续多少次查不到设备，才认定对端离线。
  ///
  /// 被控端每 10 秒续一次注册，服务端 TTL 30 秒。单次查不到可能只是恰好撞上
  /// 续期空档或一次请求失败，不足以判死。
  static const _deviceMissingThreshold = 3;

  /// 回到前台后，多久没有新帧才主动重建帧流。
  static const _resumeRebindThreshold = Duration(seconds: 2);

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
  int _jpegQuality = 75;
  int _currentMonitor = 0;
  List<String> _availableMonitors = ['主显示器'];
  bool _viewOnly = false;
  int _rotationQuarterTurns = 0;
  bool _pointerMode = false;
  int _reconnectFailureStreak = 0;
  int _deviceMissingStreak = 0;

  /// App 是否处于前台。
  ///
  /// 后台期间系统会冻结网络与定时器，任何失败都不能作为「对端不可用」的证据。
  bool _appResumed = true;

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
  int get currentMonitor => _currentMonitor;
  List<String> get availableMonitors => List.unmodifiable(_availableMonitors);

  /// 仅观看：只收画面，不向被控端发任何输入。
  bool get viewOnly => _viewOnly;

  /// 画面旋转档位（0-3，一档 90°），纯观看端行为。
  int get rotationQuarterTurns => _rotationQuarterTurns;

  /// 指针模式：本地画一个虚拟指针，拖动移动它，点击落在指针处。
  bool get pointerMode => _pointerMode;
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
    _reconnectFailureStreak = 0;
    _deviceMissingStreak = 0;
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

  void toggleViewOnly() {
    _viewOnly = !_viewOnly;
    notifyListeners();
  }

  /// 顺时针旋转画面一档。
  void rotateCanvas() {
    _rotationQuarterTurns =
        (_rotationQuarterTurns + 1) % CanvasRotation.turnCount;
    notifyListeners();
  }

  void resetCanvasRotation() {
    if (_rotationQuarterTurns == 0) return;
    _rotationQuarterTurns = 0;
    notifyListeners();
  }

  void togglePointerMode() {
    _pointerMode = !_pointerMode;
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
        _jpegQuality = 85;
      case 'medium':
        _jpegQuality = 75;
      case 'low':
        _jpegQuality = 55;
      default:
        _jpegQuality = 75;
    }
    _minFrameInterval = Duration(milliseconds: (1000 / fps).round());
    // Send quality setting to the remote host
    final session = _currentSession;
    if (session != null) {
      _bridge.sendRemoteQuality(
        session.sessionId,
        _jpegQuality / 100.0,
        fps: _fpsLimit,
      );
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
    _viewOnly = false;
    _rotationQuarterTurns = 0;
    _pointerMode = false;
    _stopClipboardSync();
    final subscription = _frameSubscription;
    _frameSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    notifyListeners();
  }

  /// 仅观看模式下所有写向被控端的输入都在这里被丢弃。
  ///
  /// 拦在 provider 层而不是各个 UI 回调里：移动端画布、桌面端侧栏、剪贴板
  /// 自动同步都从这些方法出去，只在某一处挡必然漏。
  /// 切显示器、画质不算输入，仍然放行。
  Future<bool> _blockedInput() => Future<bool>.value(false);

  Future<bool> sendTap(
      String sessionId, Offset localPosition, Size viewportSize) {
    if (_viewOnly) return _blockedInput();
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
    if (_viewOnly) return _blockedInput();
    return _bridge.sendRemoteTap(
      sessionId,
      normalizedX: normalizedPosition.dx.clamp(0.0, 1.0),
      normalizedY: normalizedPosition.dy.clamp(0.0, 1.0),
    );
  }

  Future<bool> sendAction(String sessionId, String action) {
    if (_viewOnly) return _blockedInput();
    return _bridge.sendRemoteAction(sessionId, action);
  }

  Future<bool> sendLongPress(
      String sessionId, Offset localPosition, Size viewportSize) {
    if (_viewOnly) return _blockedInput();
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
    if (_viewOnly) return _blockedInput();
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
    if (_viewOnly) return _blockedInput();
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
    if (_viewOnly) return _blockedInput();
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
    if (_viewOnly) return _blockedInput();
    final points = normalizedPoints
        .map((p) => [p.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, 1.0)])
        .toList();
    return _bridge.sendRemoteDragPath(sessionId, points);
  }

  Future<bool> sendTextInput(String sessionId, String text) {
    if (_viewOnly) return _blockedInput();
    return _bridge.sendRemoteTextInput(sessionId, text);
  }

  Future<bool> sendClipboard(String sessionId, String text) {
    if (_viewOnly) return _blockedInput();
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) {
      _appResumed = false;
      return;
    }

    final wasBackgrounded = !_appResumed;
    _appResumed = true;
    final session = _currentSession;
    if (session == null) {
      return;
    }

    final lastFrame = _lastFrameReceivedAt;
    // App 处于后台时系统会挂起帧流，这段时间本就不该有帧到达。
    // 若把它计入「多久没收到帧」，回到前台的瞬间必然超过阈值被判离线，
    // 进而触发终止逻辑退回设备列表——这正是「放后台一会儿就掉线」的成因。
    // 恢复前台时重置计时，把判定窗口让给真正的重连流程。
    _lastFrameReceivedAt = DateTime.now();
    // 后台期间累计的失败全部作废：它们证明的是「系统冻结了网络」，
    // 而不是「对端不可用」。
    _reconnectFailureStreak = 0;
    _deviceMissingStreak = 0;

    // 回到前台时帧流多半已经死了：WebSocket 被系统拆掉、轮询循环也可能停在
    // 一次失败上。等看门狗慢慢发现要好几秒，期间画面是黑的。这里主动重建。
    final stale = lastFrame == null ||
        DateTime.now().difference(lastFrame) > _resumeRebindThreshold;
    if (wasBackgrounded &&
        stale &&
        !_bridge.isSessionTerminated(session.sessionId)) {
      _connectionStatusLabel = '重连中';
      notifyListeners();
      unawaited(_bindFrameStream(session));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      _reconnectFailureStreak = 0;
      _deviceMissingStreak = 0;

      // Update session state (latency / online status) always
      final wasOffline = !_isRemoteOnline;
      _isRemoteOnline = true;
      _connectionStatusLabel = '在线';
      _currentSession = _currentSession?.copyWith(
        latencyMs: frame.latencyMs,
        clearLatency: !frame.latencyAvailable,
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
    final isDisconnected =
        lastFrame != null && now.difference(lastFrame) > _offlineGracePeriod;
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
        _reconnectFailureStreak = 0;
        _deviceMissingStreak++;
        // 只有连续多次查不到、且 App 确实在前台时才判离线。
        if (_deviceMissingStreak >= _deviceMissingThreshold && _appResumed) {
          _connectionStatusLabel = '设备离线';
          _currentSession = _currentSession?.copyWith(
            state: SessionState.disconnected,
          );
        } else {
          _connectionStatusLabel = '重连中';
          _currentSession = _currentSession?.copyWith(
            state: SessionState.reconnecting,
          );
        }
      } else if (!resolved.authorized) {
        // 授权结论来自服务端，不是网络抖动，直接采信。
        _deviceMissingStreak = 0;
        _reconnectFailureStreak = 0;
        _connectionStatusLabel = password.isEmpty ? '等待对端授权' : '密码已变更';
        _currentSession = _currentSession?.copyWith(
          state: SessionState.error,
        );
      } else {
        _deviceMissingStreak = 0;
        _reconnectFailureStreak = 0;
        _connectionStatusLabel = '已重连，等待画面';
        _currentSession = _currentSession?.copyWith(
          state: SessionState.reconnecting,
        );
      }
      notifyListeners();
    } catch (_) {
      if (_currentSession?.sessionId == session.sessionId) {
        _reconnectFailureStreak++;
        // 单次异常只说明这一刻网络不通。攒够连续失败、且 App 在前台，
        // 才允许落到会把用户踢回设备列表的终态。
        _connectionStatusLabel =
            _reconnectFailureStreak >= _reconnectFailureThreshold && _appResumed
                ? '重连失败'
                : '重连中';
        notifyListeners();
      }
    } finally {
      _reconnectInFlight = false;
    }
  }
}
