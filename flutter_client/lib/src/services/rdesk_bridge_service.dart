import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';

import '../models/account.dart';
import '../models/chat_message.dart';
import '../models/connection_info.dart';
import '../models/device.dart';
import '../models/file_entry.dart';
import '../models/trusted_peer.dart';
import '../utils/constants.dart';

class BridgeSettingsData {
  final String signalingServer;
  final String relayServer;
  final bool autoAccept;
  final bool autoClipboardSync;
  final bool rememberTrustedPeers;
  final String theme;
  final String? permanentPassword;

  const BridgeSettingsData({
    required this.signalingServer,
    required this.relayServer,
    required this.autoAccept,
    required this.autoClipboardSync,
    required this.rememberTrustedPeers,
    required this.theme,
    required this.permanentPassword,
  });
}

class RemoteFrameData {
  final Uint8List bytes;
  final int width;
  final int height;
  final int latencyMs;

  const RemoteFrameData({
    required this.bytes,
    required this.width,
    required this.height,
    required this.latencyMs,
  });
}

class PreviewResolveResult {
  final bool found;
  final bool authorized;
  final Uri? endpoint;
  final String? platform;
  final String? hostname;

  const PreviewResolveResult({
    required this.found,
    required this.authorized,
    required this.endpoint,
    required this.platform,
    required this.hostname,
  });
}

class HostedRelayCommand {
  final String commandId;
  final String kind;
  final Map<String, dynamic> payload;

  const HostedRelayCommand({
    required this.commandId,
    required this.kind,
    required this.payload,
  });

  factory HostedRelayCommand.fromJson(Map<String, dynamic> json) {
    return HostedRelayCommand(
      commandId: json['command_id'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      payload: (json['payload'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
    );
  }
}

class RdeskBridgeService {
  RdeskBridgeService._();

  static final RdeskBridgeService instance = RdeskBridgeService._();
  static const _healthyFramePollDelayMs = 50;
  static const _recoveringFramePollDelayMs = 150;
  static const _offlineFramePollDelayMs = 400;
  static const _deviceIdKey = 'rdesk.device_id';
  static const _tempPasswordKey = 'rdesk.temp_password';
  static const _connectionsKey = 'rdesk.connection_logs';
  static const _signalingServerKey = 'rdesk.signaling_server';
  static const _relayServerKey = 'rdesk.relay_server';
  static const _autoAcceptKey = 'rdesk.auto_accept';
  static const _autoClipboardSyncKey = 'rdesk.auto_clipboard_sync';
  static const _rememberTrustedPeersKey = 'rdesk.remember_trusted_peers';
  static const _themeKey = 'rdesk.theme';
  static const _permanentPasswordKey = 'rdesk.permanent_password';
  static const _trustedPeersKey = 'rdesk.trusted_peers';
  static const _trustedIncomingViewersKey = 'rdesk.trusted_incoming_viewers';
  static const _accountTokenKey = 'rdesk.account_token';
  static const _accountUserIdKey = 'rdesk.account_user_id';
  static const _accountUsernameKey = 'rdesk.account_username';
  static const _accountDisplayNameKey = 'rdesk.account_display_name';
  static const _chatPrefix = 'rdesk.chat.';
  static const _legacyServerSettings = <String>{
    'https://qisw.top',
    'http://qisw.top',
    'qisw.top',
    'https://rdesk.qisw.top',
    'http://rdesk.qisw.top',
    'rdesk.qisw.top',
    '101.37.21.147',
    '101.37.21.147:80',
    'http://101.37.21.147',
    'http://101.37.21.147:80',
    '101.37.21.147:21116',
    'http://101.37.21.147:21116',
    '124.223.200.182',
    '124.223.200.182:80',
    'http://124.223.200.182',
    'http://124.223.200.182:80',
    '124.223.200.182:21116',
    'http://124.223.200.182:21116',
    'qswnotes.com',
    'qswnotes.com:80',
    'http://qswnotes.com',
    'http://qswnotes.com:80',
    'https://qswnotes.com',
    'qswnotes.com:21116',
    'http://qswnotes.com:21116',
    'https://qswnotes.com:21116',
  };
  final Map<String, Uri> _sessionPreviewEndpoints = <String, Uri>{};
  final Map<String, String> _sessionTokens = <String, String>{};
  final Set<String> _terminatedSessions = <String>{};

  // ── Secure storage for passwords and credentials ──
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // ── Persistent HTTP clients for connection reuse (keep-alive) ──
  HttpClient? _frameClient;
  HttpClient? _controlClient;

  HttpClient get _getFrameClient {
    _frameClient ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 3)
      ..idleTimeout = const Duration(seconds: 15);
    return _frameClient!;
  }

  HttpClient get _getControlClient {
    _controlClient ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 2)
      ..idleTimeout = const Duration(seconds: 15);
    return _controlClient!;
  }

  /// Closes persistent HTTP clients (call on disconnect).
  void closePersistentClients() {
    _frameClient?.close();
    _frameClient = null;
    _controlClient?.close();
    _controlClient = null;
  }

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  String get defaultBrowserPath => Platform.environment['HOME'] ?? '/';

  Future<DeviceInfo> getLocalDeviceInfo() async {
    final prefs = await _prefs;
    var deviceId = prefs.getString(_deviceIdKey);
    if (deviceId == null || deviceId.length != AppConstants.deviceIdLength) {
      deviceId = _generateDigits(AppConstants.deviceIdLength);
      await prefs.setString(_deviceIdKey, deviceId);
    }

    return DeviceInfo(
      deviceId: deviceId,
      os: Platform.operatingSystem,
      hostname: await _getDeviceName(),
      version: AppConstants.version,
    );
  }

  Future<String> _getDeviceName() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        return android.model;
      } else if (Platform.isIOS) {
        final ios = await info.iosInfo;
        return ios.name;
      } else if (Platform.isMacOS) {
        final macos = await info.macOsInfo;
        return macos.computerName;
      }
    } catch (_) {
      // Fall through to Platform.localHostname
    }
    final fallback = Platform.localHostname;
    return (fallback.isNotEmpty && fallback != 'localhost')
        ? fallback
        : '${Platform.operatingSystem} 设备';
  }

  Future<String> generateTemporaryPassword() async {
    final prefs = await _prefs;
    final password = _generateAlphaNumeric(AppConstants.tempPasswordLength);
    await prefs.setString(_tempPasswordKey, password);
    return password;
  }

  Future<String> getTemporaryPassword() async {
    final prefs = await _prefs;
    final cached = prefs.getString(_tempPasswordKey);
    if (cached != null && cached.isNotEmpty) return cached;
    return generateTemporaryPassword();
  }

  Future<String> connectToPeer(String deviceId, String password) async {
    if (deviceId.length != AppConstants.deviceIdLength) {
      throw Exception('设备ID必须是9位数字');
    }

    final localDevice = await getLocalDeviceInfo();
    final resolved = await _resolvePreviewEndpoint(
      deviceId,
      password: password,
      requesterId: localDevice.deviceId,
    );
    if (!resolved.found) {
      throw Exception('未找到在线设备，请确认对方已启动共享服务');
    }
    if (!resolved.authorized) {
      if (password.isEmpty) {
        throw Exception('对方拒绝了连接请求或未在规定时间内响应');
      }
      throw Exception('连接密码错误');
    }
    final targetPlatform = (resolved.platform ?? '').toLowerCase();
    if (targetPlatform == 'ios' ||
        targetPlatform == 'iphone' ||
        targetPlatform == 'ipad' ||
        targetPlatform.contains('ios')) {
      throw Exception('当前 iPhone/iPad 端仅支持发起连接，不支持被远程控制');
    }
    final sessionId = 'session-${DateTime.now().millisecondsSinceEpoch}';
    _terminatedSessions.remove(sessionId);
    if (resolved.endpoint != null) {
      _sessionPreviewEndpoints[sessionId] = resolved.endpoint!;
    }
    final settings = await loadSettings();
    if (settings.rememberTrustedPeers && password.isNotEmpty) {
      await rememberTrustedPeer(
        deviceId: deviceId,
        password: password,
        hostname: resolved.hostname ?? '远程设备 $deviceId',
        peerOs: resolved.platform ?? 'android-preview',
      );
    }
    await _trustViewerOnRemote(
      sessionId: sessionId,
      requester: localDevice,
    );
    final records = await listConnectionHistory();
    final updated = <ConnectionRecord>[
      ConnectionRecord(
        peerId: deviceId,
        peerHostname: resolved.hostname ?? '远程设备 $deviceId',
        peerOs: resolved.platform ?? 'android-preview',
        connectedAt: DateTime.now(),
        connectionType: 'preview-registry',
        status: 'success',
      ),
      ...records,
    ];
    await _saveConnectionHistory(updated.take(12).toList());
    return sessionId;
  }

  /// Direct IP connection (LAN / Tailscale) — bypasses signaling server.
  /// [address] can be "IP:Port" (e.g. "100.64.1.2:12345") or just "IP"
  /// (defaults to port 21116 when omitted).
  /// [password] is the access password for the remote host (may be empty if
  /// the host has no password set).
  Future<String> connectDirectIp(String address, {String? password}) async {
    String host;
    int port;
    if (address.contains(':')) {
      final parts = address.split(':');
      host = parts[0];
      port = int.tryParse(parts[1]) ?? 21116;
    } else {
      host = address;
      port = 21116;
    }

    // Probe host health endpoint
    final healthUri = Uri.http('$host:$port', '/health');
    debugPrint('[RDesk] connectDirectIp: probing $healthUri');
    try {
      final request = await HttpClient()
          .getUrl(healthUri)
          .timeout(const Duration(seconds: 3));
      final response =
          await request.close().timeout(const Duration(seconds: 3));
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw Exception('无法连接到 $host:$port（HTTP ${response.statusCode}）');
      }
      final body = await utf8.decoder.bind(response).join();
      final payload = jsonDecode(body) as Map<String, dynamic>;
      final platform = payload['platform'] as String? ?? 'unknown';
      final running = payload['running'] as bool? ?? false;
      debugPrint('[RDesk] connectDirectIp: health OK, platform=$platform, '
          'running=$running');
      if (!running) {
        throw Exception('远程设备未启动共享服务');
      }
    } on TimeoutException {
      throw Exception('连接超时：无法连接到 $host:$port，请检查 IP 和端口');
    } on SocketException catch (e) {
      throw Exception('无法连接到 $host:$port（${e.message}）');
    }

    // Create session pointing directly at the host LAN HTTP server
    final sessionId = 'direct-${DateTime.now().millisecondsSinceEpoch}';
    final endpoint = Uri.http('$host:$port', '/frame.jpg');
    _terminatedSessions.remove(sessionId);
    _sessionPreviewEndpoints[sessionId] = endpoint;

    // Authenticate with the host via /session/trust (password required).
    final localDevice = await getLocalDeviceInfo();
    await _trustViewerOnRemote(
      sessionId: sessionId,
      requester: localDevice,
      password: password,
    );

    // Verify we obtained a session token — without it all protected endpoints
    // will return 401 and the session is unusable.
    if (!_sessionTokens.containsKey(sessionId)) {
      _sessionPreviewEndpoints.remove(sessionId);
      throw Exception('认证失败：密码错误或远程设备拒绝连接');
    }

    final records = await listConnectionHistory();
    final updated = <ConnectionRecord>[
      ConnectionRecord(
        peerId: address,
        peerHostname: '直连 $address',
        peerOs: 'direct-lan',
        connectedAt: DateTime.now(),
        connectionType: 'direct-ip',
        status: 'success',
      ),
      ...records,
    ];
    await _saveConnectionHistory(updated.take(12).toList());

    return sessionId;
  }

  Stream<RemoteFrameData?> watchSessionFrames(
    String sessionId, {
    required String peerId,
  }) async* {
    // Try WebSocket first for lower latency
    final endpoint = _sessionPreviewEndpoints[sessionId];
    if (endpoint != null) {
      debugPrint('[RDesk] watchSessionFrames: trying WebSocket for $sessionId');
      final wsStream = _tryWebSocketStream(sessionId, endpoint);
      if (wsStream != null) {
        yield* wsStream;
        if (_terminatedSessions.contains(sessionId)) {
          debugPrint(
              '[RDesk] watchSessionFrames: session terminated, stopping');
          return;
        }
        debugPrint('[RDesk] watchSessionFrames: WebSocket ended, '
            'falling through to HTTP polling');
      }
    }

    // Fallback to HTTP polling
    debugPrint('[RDesk] watchSessionFrames: starting HTTP polling for '
        '$sessionId (endpoint=${endpoint ?? 'null'})');
    yield* _watchSessionFramesHttp(sessionId, peerId: peerId);
  }

  Stream<RemoteFrameData?>? _tryWebSocketStream(
      String sessionId, Uri httpEndpoint) {
    try {
      final params = httpEndpoint.queryParameters;
      final deviceId = params['device_id'];
      final token = params['token'];
      if (deviceId == null || token == null) return null;

      final wsScheme = httpEndpoint.scheme == 'https' ? 'wss' : 'ws';
      final wsUri = Uri(
        scheme: wsScheme,
        host: httpEndpoint.host,
        port: httpEndpoint.port,
        path: '/ws/viewer/$deviceId',
        queryParameters: {'token': token},
      );

      final controller = StreamController<RemoteFrameData?>();
      IOWebSocketChannel? channel;
      Timer? frameWatchdog;
      var lastFrameAt = DateTime.now();
      int? wsLatencyBaselineMs;
      const wsFrameTimeout = Duration(seconds: 6);

      int normalizeWebSocketLatency(int rawLatencyMs) {
        if (rawLatencyMs < 0) {
          return 0;
        }
        wsLatencyBaselineMs = wsLatencyBaselineMs == null
            ? rawLatencyMs
            : min(wsLatencyBaselineMs!, rawLatencyMs);
        final baselineMs = wsLatencyBaselineMs!;
        if (baselineMs >= 1500) {
          return (rawLatencyMs - baselineMs).clamp(0, 9999).toInt();
        }
        return rawLatencyMs.clamp(0, 9999).toInt();
      }

      void closeStream() {
        frameWatchdog?.cancel();
        frameWatchdog = null;
        channel?.sink.close();
        if (!controller.isClosed) {
          controller.add(null);
          controller.close();
        }
      }

      void connect() {
        try {
          channel = IOWebSocketChannel.connect(wsUri,
              connectTimeout: const Duration(seconds: 5));
          frameWatchdog = Timer.periodic(const Duration(seconds: 1), (_) {
            if (controller.isClosed) return;
            if (_terminatedSessions.contains(sessionId)) {
              closeStream();
              return;
            }
            if (DateTime.now().difference(lastFrameAt) >= wsFrameTimeout) {
              // WebSocket produced no frames within timeout.
              // Close the stream so watchSessionFrames falls through
              // to HTTP polling.
              closeStream();
            }
          });
          channel!.stream.listen(
            (message) {
              if (_terminatedSessions.contains(sessionId)) {
                closeStream();
                return;
              }
              if (message is List<int>) {
                final bytes = message is Uint8List
                    ? message
                    : Uint8List.fromList(message);
                final receivedAtMs = DateTime.now().millisecondsSinceEpoch;
                final frame = _decodeRemoteFramePacket(
                  bytes,
                  receivedAtMs: receivedAtMs,
                  normalizeLatency: normalizeWebSocketLatency,
                );
                if (frame == null) {
                  return;
                }
                lastFrameAt =
                    DateTime.fromMillisecondsSinceEpoch(receivedAtMs);
                controller.add(frame);
              }
            },
            onError: (_) => closeStream(),
            onDone: () => closeStream(),
          );
        } catch (_) {
          closeStream();
        }
      }

      controller.onCancel = () {
        frameWatchdog?.cancel();
        channel?.sink.close();
      };
      controller.onPause = () => frameWatchdog?.cancel();
      controller.onResume = () {
        lastFrameAt = DateTime.now();
        frameWatchdog ??= Timer.periodic(const Duration(seconds: 1), (_) {
          if (controller.isClosed) return;
          if (_terminatedSessions.contains(sessionId)) {
            closeStream();
            return;
          }
          if (DateTime.now().difference(lastFrameAt) >= wsFrameTimeout) {
            closeStream();
          }
        });
      };
      controller.done.whenComplete(() {
        frameWatchdog?.cancel();
        frameWatchdog = null;
      });

      connect();
      return controller.stream;
    } catch (_) {
      return null;
    }
  }

  Stream<RemoteFrameData?> _watchSessionFramesHttp(
    String sessionId, {
    required String peerId,
  }) async* {
    int consecutiveErrors = 0;
    for (var tick = 0; true; tick++) {
      if (_terminatedSessions.contains(sessionId)) {
        yield null;
        return;
      }

      final endpoint = _sessionPreviewEndpoints[sessionId];
      final remoteFrame = await _fetchRemotePreviewFrame(
        sessionId,
        endpoint: endpoint,
      );
      if (remoteFrame != null) {
        consecutiveErrors = 0;
        yield remoteFrame;
      } else if (_sessionPreviewEndpoints.containsKey(sessionId)) {
        consecutiveErrors++;
        // If the session was terminated by _fetchRemotePreviewFrame (401 or
        // SocketException), stop polling immediately.
        if (_terminatedSessions.contains(sessionId)) {
          yield null;
          return;
        }
        yield null;
      } else {
        yield await _renderDemoFrame(
          sessionId: sessionId,
          peerId: peerId,
          tick: tick,
        );
      }
      final delayMs = consecutiveErrors > 5
          ? _offlineFramePollDelayMs
          : consecutiveErrors > 0
              ? _recoveringFramePollDelayMs
              : _healthyFramePollDelayMs;
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
  }

  Future<void> disconnect(String sessionId) async {
    _terminatedSessions.add(sessionId);
    _sessionPreviewEndpoints.remove(sessionId);
    _sessionTokens.remove(sessionId);
    closePersistentClients();
  }

  Future<List<ConnectionRecord>> listConnectionHistory() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_connectionsKey);
    if (raw == null || raw.isEmpty) return [];
    final data =
        (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    return data
        .map(
          (item) => ConnectionRecord(
            peerId: item['peerId'] as String,
            peerHostname: item['peerHostname'] as String,
            peerOs: item['peerOs'] as String,
            connectedAt: DateTime.parse(item['connectedAt'] as String),
            disconnectedAt: item['disconnectedAt'] == null
                ? null
                : DateTime.parse(item['disconnectedAt'] as String),
            connectionType: item['connectionType'] as String,
            status: item['status'] as String? ?? 'success',
            failureReason: item['failureReason'] as String?,
          ),
        )
        .toList();
  }

  Future<void> recordConnectionFailure({
    required String peerId,
    required String failureReason,
  }) async {
    final records = await listConnectionHistory();
    final updated = <ConnectionRecord>[
      ConnectionRecord(
        peerId: peerId,
        peerHostname: '远程设备 $peerId',
        peerOs: '未知系统',
        connectedAt: DateTime.now(),
        connectionType: 'preview-registry',
        status: 'failed',
        failureReason: failureReason,
      ),
      ...records,
    ];
    await _saveConnectionHistory(updated.take(12).toList());
  }

  Future<BridgeSettingsData> loadSettings() async {
    final prefs = await _prefs;
    final storedSignalingServer = prefs.getString(_signalingServerKey);
    final storedRelayServer = prefs.getString(_relayServerKey);
    final signalingServer = _migrateServerSetting(
      storedSignalingServer,
      AppConstants.defaultSignalingServer,
    );
    final relayServer = _migrateServerSetting(
      storedRelayServer,
      AppConstants.defaultRelayServer,
    );
    if (storedSignalingServer != signalingServer) {
      await prefs.setString(_signalingServerKey, signalingServer);
    }
    if (storedRelayServer != relayServer) {
      await prefs.setString(_relayServerKey, relayServer);
    }
    return BridgeSettingsData(
      signalingServer: signalingServer,
      relayServer: relayServer,
      autoAccept: prefs.getBool(_autoAcceptKey) ?? false,
      autoClipboardSync: prefs.getBool(_autoClipboardSyncKey) ?? false,
      rememberTrustedPeers: prefs.getBool(_rememberTrustedPeersKey) ?? true,
      theme: prefs.getString(_themeKey) ?? 'system',
      permanentPassword: await _secureStorage.read(key: _permanentPasswordKey),
    );
  }

  String _migrateServerSetting(String? storedValue, String fallback) {
    final value = storedValue?.trim();
    if (value == null || value.isEmpty) {
      return fallback;
    }
    final normalized = value.toLowerCase().replaceFirst(RegExp(r'/+$'), '');
    return _legacyServerSettings.contains(normalized) ? fallback : value;
  }

  Future<void> saveSettings({
    String? signalingServer,
    String? relayServer,
    bool? autoAccept,
    bool? autoClipboardSync,
    bool? rememberTrustedPeers,
    String? theme,
  }) async {
    final prefs = await _prefs;
    if (signalingServer != null) {
      await prefs.setString(_signalingServerKey, signalingServer);
    }
    if (relayServer != null) {
      await prefs.setString(_relayServerKey, relayServer);
    }
    if (autoAccept != null) {
      await prefs.setBool(_autoAcceptKey, autoAccept);
    }
    if (autoClipboardSync != null) {
      await prefs.setBool(_autoClipboardSyncKey, autoClipboardSync);
    }
    if (rememberTrustedPeers != null) {
      await prefs.setBool(_rememberTrustedPeersKey, rememberTrustedPeers);
    }
    if (theme != null) {
      await prefs.setString(_themeKey, theme);
    }
  }

  Future<List<TrustedPeer>> listTrustedPeers() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_trustedPeersKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    final data =
        (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    final peers = data
        .map(
          (item) => TrustedPeer(
            deviceId: item['deviceId'] as String,
            hostname: item['hostname'] as String,
            peerOs: item['peerOs'] as String,
            savedAt: DateTime.parse(item['savedAt'] as String),
            lastUsedAt: DateTime.parse(item['lastUsedAt'] as String),
          ),
        )
        .toList();
    peers.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    return peers;
  }

  Future<String?> getTrustedPeerPassword(String deviceId) async {
    // Read from secure storage (keyed per device).
    return _secureStorage.read(key: '${_trustedPeersKey}.pw.$deviceId');
  }

  Future<void> rememberTrustedPeer({
    required String deviceId,
    required String password,
    required String hostname,
    required String peerOs,
  }) async {
    // Store password in secure storage (keyed per device).
    await _secureStorage.write(
      key: '${_trustedPeersKey}.pw.$deviceId',
      value: password,
    );
    // Store metadata (without password) in SharedPreferences.
    final prefs = await _prefs;
    final raw = prefs.getString(_trustedPeersKey);
    final data = raw == null || raw.isEmpty
        ? <Map<String, dynamic>>[]
        : (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    final now = DateTime.now().toIso8601String();
    data.removeWhere((item) => item['deviceId'] == deviceId);
    data.insert(0, <String, dynamic>{
      'deviceId': deviceId,
      'hostname': hostname,
      'peerOs': peerOs,
      'savedAt': now,
      'lastUsedAt': now,
    });
    await prefs.setString(_trustedPeersKey, jsonEncode(data.take(20).toList()));
  }

  Future<void> touchTrustedPeer(String deviceId) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_trustedPeersKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    final data =
        (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    final index = data.indexWhere((item) => item['deviceId'] == deviceId);
    if (index < 0) {
      return;
    }
    final updated = Map<String, dynamic>.from(data[index]);
    updated['lastUsedAt'] = DateTime.now().toIso8601String();
    data.removeAt(index);
    data.insert(0, updated);
    await prefs.setString(_trustedPeersKey, jsonEncode(data));
  }

  Future<void> removeTrustedPeer(String deviceId) async {
    // Remove password from secure storage.
    await _secureStorage.delete(key: '${_trustedPeersKey}.pw.$deviceId');
    final prefs = await _prefs;
    final raw = prefs.getString(_trustedPeersKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    final data =
        (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    data.removeWhere((item) => item['deviceId'] == deviceId);
    await prefs.setString(_trustedPeersKey, jsonEncode(data));
  }

  Future<void> clearTrustedPeers() async {
    final prefs = await _prefs;
    await prefs.remove(_trustedPeersKey);
  }

  Future<List<TrustedPeer>> listTrustedIncomingViewers() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_trustedIncomingViewersKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    final data =
        (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    final viewers = data
        .map(
          (item) => TrustedPeer(
            deviceId: item['deviceId'] as String,
            hostname: item['hostname'] as String,
            peerOs: item['peerOs'] as String,
            savedAt: DateTime.parse(item['savedAt'] as String),
            lastUsedAt: DateTime.parse(item['lastUsedAt'] as String),
          ),
        )
        .toList();
    viewers.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    return viewers;
  }

  Future<List<String>> listTrustedIncomingViewerIds() async {
    final viewers = await listTrustedIncomingViewers();
    return viewers.map((item) => item.deviceId).toList();
  }

  Future<void> trustIncomingViewer({
    required String deviceId,
    required String hostname,
    required String peerOs,
  }) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_trustedIncomingViewersKey);
    final data = raw == null || raw.isEmpty
        ? <Map<String, dynamic>>[]
        : (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    final now = DateTime.now().toIso8601String();
    data.removeWhere((item) => item['deviceId'] == deviceId);
    data.insert(0, <String, dynamic>{
      'deviceId': deviceId,
      'hostname': hostname,
      'peerOs': peerOs,
      'savedAt': now,
      'lastUsedAt': now,
    });
    await prefs.setString(
      _trustedIncomingViewersKey,
      jsonEncode(data.take(20).toList()),
    );
  }

  Future<void> removeTrustedIncomingViewer(String deviceId) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_trustedIncomingViewersKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    final data =
        (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    data.removeWhere((item) => item['deviceId'] == deviceId);
    await prefs.setString(_trustedIncomingViewersKey, jsonEncode(data));
  }

  Future<void> clearTrustedIncomingViewers() async {
    final prefs = await _prefs;
    await prefs.remove(_trustedIncomingViewersKey);
  }

  Future<void> setPermanentPassword(String? password) async {
    if (password == null || password.isEmpty) {
      await _secureStorage.delete(key: _permanentPasswordKey);
      return;
    }
    await _secureStorage.write(key: _permanentPasswordKey, value: password);
  }

  Future<String> getActiveAccessPassword() async {
    final settings = await loadSettings();
    final permanent = settings.permanentPassword?.trim();
    if (permanent != null && permanent.isNotEmpty) {
      return permanent;
    }
    return getTemporaryPassword();
  }

  Future<AccountSession?> getSavedAccountSession() async {
    final prefs = await _prefs;
    final token = prefs.getString(_accountTokenKey);
    final userId = prefs.getString(_accountUserIdKey);
    final username = prefs.getString(_accountUsernameKey);
    if (token == null || userId == null || username == null) {
      return null;
    }
    return AccountSession(
      token: token,
      userId: userId,
      username: username,
      displayName: prefs.getString(_accountDisplayNameKey) ?? username,
    );
  }

  Future<void> saveAccountSession(AccountSession session) async {
    final prefs = await _prefs;
    await prefs.setString(_accountTokenKey, session.token);
    await prefs.setString(_accountUserIdKey, session.userId);
    await prefs.setString(_accountUsernameKey, session.username);
    await prefs.setString(_accountDisplayNameKey, session.displayName);
  }

  Future<void> clearSavedAccountSession() async {
    final prefs = await _prefs;
    await prefs.remove(_accountTokenKey);
    await prefs.remove(_accountUserIdKey);
    await prefs.remove(_accountUsernameKey);
    await prefs.remove(_accountDisplayNameKey);
  }

  Future<String?> getAccountToken() async {
    final session = await getSavedAccountSession();
    return session?.token;
  }

  Future<AccountSession> registerAccount({
    required String username,
    required String password,
    String? displayName,
  }) async {
    final payload = await _postJson(
      path: '/api/account/register',
      body: <String, Object?>{
        'username': username.trim(),
        'password': password,
        'display_name': displayName?.trim(),
      },
    );
    return _parseAccountSession(payload);
  }

  Future<AccountSession> loginAccount({
    required String username,
    required String password,
  }) async {
    final payload = await _postJson(
      path: '/api/account/login',
      body: <String, Object?>{
        'username': username.trim(),
        'password': password,
      },
    );
    return _parseAccountSession(payload);
  }

  Future<List<AccountDevice>> listAccountDevices() async {
    final session = await getSavedAccountSession();
    if (session == null) {
      return const [];
    }
    await _upsertAccountPresence(session);
    final payload = await _getJson(
      path: '/api/account/devices',
      bearerToken: session.token,
    );
    final rawDevices = payload['devices'] as List<dynamic>? ?? const [];
    return rawDevices
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .map(
          (item) => AccountDevice(
            deviceId: '${item['device_id'] ?? ''}'.trim(),
            hostname: ('${item['hostname'] ?? ''}'.trim()).isEmpty
                ? '未命名设备'
                : '${item['hostname']}'.trim(),
            platform: ('${item['platform'] ?? ''}'.trim()).isEmpty
                ? 'unknown'
                : '${item['platform']}'.trim(),
            updatedAtMs: (item['updated_at_ms'] as num?)?.toInt() ?? 0,
          ),
        )
        .where((item) => item.deviceId.isNotEmpty)
        .toList();
  }

  Future<void> _upsertAccountPresence(AccountSession session) async {
    final local = await getLocalDeviceInfo();
    try {
      await _postJson(
        path: '/api/account/presence',
        bearerToken: session.token,
        body: <String, Object?>{
          'device_id': local.deviceId.trim(),
          'platform': local.os.trim(),
          'hostname': local.hostname.trim(),
        },
      );
    } catch (_) {
      // Presence heartbeat is best effort and should not block listing devices.
    }
  }

  Future<List<ChatMessage>> listChatMessages(String sessionId) async {
    final prefs = await _prefs;
    final raw = prefs.getString('$_chatPrefix$sessionId');
    if (raw == null || raw.isEmpty) return [];
    final data =
        (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    return data
        .map(
          (item) => ChatMessage(
            sender: item['sender'] as String,
            content: item['content'] as String,
            timestamp: DateTime.parse(item['timestamp'] as String),
            isLocal: item['isLocal'] as bool,
          ),
        )
        .toList();
  }

  Future<ChatMessage> sendChatMessage(String sessionId, String content) async {
    final messages = await listChatMessages(sessionId);
    final message = ChatMessage(
      sender: '我',
      content: content,
      timestamp: DateTime.now(),
      isLocal: true,
    );
    messages.add(message);
    await _saveChatMessages(sessionId, messages);
    return message;
  }

  Future<void> injectRemoteMessage(String sessionId, String content) async {
    final messages = await listChatMessages(sessionId);
    messages.add(
      ChatMessage(
        sender: '远程端',
        content: content,
        timestamp: DateTime.now(),
        isLocal: false,
      ),
    );
    await _saveChatMessages(sessionId, messages);
  }

  Future<List<FileEntry>> listLocalDirectory(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) return [];

    final children = await directory.list(followLinks: false).toList();
    final entries = <FileEntry>[];
    for (final entity in children) {
      try {
        final stat = await entity.stat();
        entries.add(
          FileEntry(
            name: entity.uri.pathSegments.isEmpty
                ? entity.path
                : entity.uri.pathSegments
                    .where((segment) => segment.isNotEmpty)
                    .last,
            isDir: stat.type == FileSystemEntityType.directory,
            size: stat.size,
            modified: stat.modified,
          ),
        );
      } catch (_) {
        // Ignore files we cannot stat.
      }
    }
    entries.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  Future<List<FileEntry>> listRemoteDirectory(
      String sessionId, String path) async {
    final endpoint = _sessionPreviewEndpoints[sessionId];
    if (endpoint == null) {
      throw Exception('会话不存在或已断开，无法浏览远程目录');
    }

    final params = endpoint.queryParameters;
    final deviceId = params['device_id'];
    final token = params['token'];
    if (deviceId == null || token == null) {
      throw Exception('缺少远程设备凭据，无法浏览远程目录');
    }

    try {
      final settings = await loadSettings();
      final apiBase = _normalizeApiBaseUri(settings.signalingServer.trim());
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final request = await client.postUrl(
        apiBase.replace(path: '/api/file/list'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'device_id': deviceId,
        'token': token,
        'path': path,
      }));
      final response = await request.close();
      if (response.statusCode == HttpStatus.ok) {
        final body = await utf8.decoder.bind(response).join();
        final data = jsonDecode(body);
        final filesJson = data['files'];
        if (filesJson is String) {
          final list = jsonDecode(filesJson) as List;
          return list
              .map((e) => FileEntry(
                    name: e['name'] ?? '',
                    isDir: e['isDir'] == true,
                    size: e['size'] ?? 0,
                    modified: e['modified'] != null
                        ? DateTime.fromMillisecondsSinceEpoch(e['modified'])
                        : DateTime.now(),
                  ))
              .toList();
        }
      }
      client.close();
    } catch (e) {
      throw Exception('远程目录读取失败：$e');
    }
    throw Exception('远程目录读取失败：服务端返回了无法解析的数据');
  }

  Future<void> uploadFile(
      String sessionId, String localPath, String remotePath) async {
    final endpoint = _sessionPreviewEndpoints[sessionId];
    if (endpoint == null) return;

    final params = endpoint.queryParameters;
    final deviceId = params['device_id'];
    final token = params['token'];
    if (deviceId == null || token == null) return;

    try {
      final settings = await loadSettings();
      final apiBase = _normalizeApiBaseUri(settings.signalingServer.trim());
      final file = File(localPath);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      final filename = localPath.split('/').last;

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      final request = await client.postUrl(
        apiBase.replace(
          path: '/api/file/upload',
          queryParameters: {
            'device_id': deviceId,
            'token': token,
            'filename': filename,
            'remote_path': remotePath,
          },
        ),
      );
      request.headers.contentType = ContentType('application', 'octet-stream');
      request.add(bytes);
      final response = await request.close();
      await response.drain<void>();
      client.close();
    } catch (_) {}
  }

  Future<void> downloadFile(
      String sessionId, String remotePath, String localPath) async {
    // Download is not yet implemented — fail explicitly instead of faking success.
    throw UnimplementedError('远程文件下载功能尚未实现');
  }

  Future<String?> registerPreviewHost({
    required String deviceId,
    required String endpoint,
    required String platform,
    required String hostname,
    required String password,
    required bool autoAccept,
    required List<String> trustedViewerIds,
    String? authToken,
    String? hostToken,
  }) async {
    final settings = await loadSettings();
    final apiBase = _normalizeApiBaseUri(settings.signalingServer.trim());
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);

    try {
      final request =
          await client.postUrl(apiBase.replace(path: '/api/preview/register'));
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode(<String, Object?>{
          'device_id': deviceId,
          'endpoint': endpoint,
          'platform': platform,
          'hostname': hostname,
          'password_hash': _hashAccessSecret(password),
          'auto_accept': autoAccept,
          'trusted_viewers': trustedViewerIds,
          'auth_token': authToken,
          'host_token': hostToken,
        }),
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('register failed: ${response.statusCode}',
            uri: apiBase);
      }
      final body = await utf8.decoder.bind(response).join();
      if (body.isEmpty) {
        return null;
      }
      final payload = jsonDecode(body) as Map<String, dynamic>;
      return payload['host_token'] as String?;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> unregisterPreviewHost(String deviceId,
      {required String hostToken}) async {
    final settings = await loadSettings();
    final apiBase = _normalizeApiBaseUri(settings.signalingServer.trim());
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);

    try {
      final request = await client
          .postUrl(apiBase.replace(path: '/api/preview/unregister'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(<String, String>{
        'device_id': deviceId,
        'host_token': hostToken,
      }));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('unregister failed: ${response.statusCode}',
            uri: apiBase);
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> disconnectHostedViewers({
    required String deviceId,
    required String hostToken,
  }) async {
    final settings = await loadSettings();
    final apiBase = _normalizeApiBaseUri(settings.signalingServer.trim());
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);

    try {
      final request = await client
          .postUrl(apiBase.replace(path: '/api/preview/disconnect_viewers'));
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode(<String, String>{
          'device_id': deviceId,
          'host_token': hostToken,
        }),
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return false;
      }
      final body = await utf8.decoder.bind(response).join();
      if (body.isEmpty) return true;
      final payload = jsonDecode(body) as Map<String, dynamic>;
      return payload['ok'] != false;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> uploadRelayPreviewFrame({
    required String deviceId,
    required String hostToken,
    required Uint8List bytes,
    required int width,
    required int height,
    required int timestampMs,
  }) async {
    final settings = await loadSettings();
    final apiBase = _normalizeApiBaseUri(settings.signalingServer.trim());
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);

    try {
      final request = await client.postUrl(
        apiBase.replace(
          path: '/api/preview/host/frame',
          queryParameters: <String, String>{
            'device_id': deviceId,
            'host_token': hostToken,
            'width': width.toString(),
            'height': height.toString(),
            'timestamp_ms': timestampMs.toString(),
          },
        ),
      );
      request.headers.contentType = ContentType('image', 'jpeg');
      request.add(bytes);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('frame upload failed: ${response.statusCode}',
            uri: apiBase);
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<HostedRelayCommand?> pollHostedCommand({
    required String deviceId,
    required String hostToken,
  }) async {
    final settings = await loadSettings();
    final apiBase = _normalizeApiBaseUri(settings.signalingServer.trim());
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);

    try {
      final request = await client.getUrl(
        apiBase.replace(
          path: '/api/preview/host/control/poll',
          queryParameters: <String, String>{
            'device_id': deviceId,
            'host_token': hostToken,
          },
        ),
      );
      final response = await request.close();
      if (response.statusCode == HttpStatus.noContent) {
        return null;
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'command poll failed: ${response.statusCode}',
          uri: apiBase,
        );
      }
      final body = await utf8.decoder.bind(response).join();
      if (body.isEmpty) {
        return null;
      }
      final payload = jsonDecode(body) as Map<String, dynamic>;
      return HostedRelayCommand.fromJson(payload);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> submitHostedCommandResult({
    required String deviceId,
    required String hostToken,
    required String commandId,
    required bool ok,
    String? text,
  }) async {
    final settings = await loadSettings();
    final apiBase = _normalizeApiBaseUri(settings.signalingServer.trim());
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);

    try {
      final request = await client.postUrl(
        apiBase.replace(
          path: '/api/preview/host/control/result',
          queryParameters: <String, String>{
            'device_id': deviceId,
            'host_token': hostToken,
          },
        ),
      );
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode(<String, Object?>{
          'command_id': commandId,
          'ok': ok,
          'text': text,
        }),
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'command result failed: ${response.statusCode}',
          uri: apiBase,
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<PreviewResolveResult> refreshSessionEndpoint(
    String sessionId, {
    required String deviceId,
    required String password,
  }) async {
    // If the session was terminated (e.g. host actively disconnected), do not
    // attempt to resolve a new endpoint — the viewer should exit, not silently
    // reconnect to the same host.
    if (_terminatedSessions.contains(sessionId)) {
      return const PreviewResolveResult(
        found: false,
        authorized: false,
        endpoint: null,
        platform: null,
        hostname: null,
      );
    }
    final localDevice = await getLocalDeviceInfo();
    final resolved = await _resolvePreviewEndpoint(
      deviceId,
      password: password,
      requesterId: localDevice.deviceId,
    );
    // Recheck after async gap — termination may have happened while awaiting.
    if (_terminatedSessions.contains(sessionId)) {
      return const PreviewResolveResult(
        found: false,
        authorized: false,
        endpoint: null,
        platform: null,
        hostname: null,
      );
    }
    if (resolved.found && resolved.authorized && resolved.endpoint != null) {
      _sessionPreviewEndpoints[sessionId] = resolved.endpoint!;
    }
    return resolved;
  }

  bool isSessionTerminated(String sessionId) {
    return _terminatedSessions.contains(sessionId);
  }

  // ── Fast control command helper (reuses persistent client) ──
  Future<bool> _postControl(Uri uri, Map<String, dynamic> body) async {
    try {
      final request = await _getControlClient.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        debugPrint('[RDesk] _postControl FAILED: ${response.statusCode} '
            'for ${uri.path}');
        await response.drain<void>();
        return false;
      }
      final respBody = await utf8.decoder.bind(response).join();
      if (respBody.isEmpty) return true;
      final payload = jsonDecode(respBody) as Map<String, dynamic>;
      final ok = payload['ok'] != false;
      debugPrint('[RDesk] _postControl ${uri.path}: ok=$ok');
      return ok;
    } catch (e) {
      debugPrint('[RDesk] _postControl ERROR for ${uri.path}: $e');
      return false;
    }
  }

  Future<bool> sendRemoteTap(
    String sessionId, {
    required double normalizedX,
    required double normalizedY,
  }) async {
    final controlUri = _resolveControlUri(sessionId, '/input/tap');
    debugPrint(
        '[RDesk] sendRemoteTap: sessionId=$sessionId x=$normalizedX y=$normalizedY uri=$controlUri');
    if (controlUri == null) {
      debugPrint(
          '[RDesk] sendRemoteTap: controlUri is null! endpoints=$_sessionPreviewEndpoints');
      return false;
    }
    return _postControl(controlUri, <String, double>{
      'x': normalizedX.clamp(0, 1),
      'y': normalizedY.clamp(0, 1),
    });
  }

  Future<bool> sendRemoteAction(String sessionId, String action) async {
    final controlUri = _resolveControlUri(sessionId, '/input/action');
    if (controlUri == null) return false;
    return _postControl(controlUri, <String, String>{'action': action});
  }

  Future<bool> sendRemoteLongPress(
    String sessionId, {
    required double normalizedX,
    required double normalizedY,
  }) async {
    final controlUri = _resolveControlUri(sessionId, '/input/long_press');
    if (controlUri == null) return false;
    return _postControl(controlUri, <String, double>{
      'x': normalizedX.clamp(0, 1),
      'y': normalizedY.clamp(0, 1),
    });
  }

  Future<bool> sendRemoteDrag(
    String sessionId, {
    required double startX,
    required double startY,
    required double endX,
    required double endY,
  }) async {
    final controlUri = _resolveControlUri(sessionId, '/input/drag');
    if (controlUri == null) return false;
    return _postControl(controlUri, <String, double>{
      'startX': startX.clamp(0, 1),
      'startY': startY.clamp(0, 1),
      'endX': endX.clamp(0, 1),
      'endY': endY.clamp(0, 1),
    });
  }

  Future<bool> sendRemoteDragPath(
    String sessionId,
    List<List<double>> points,
  ) async {
    final controlUri = _resolveControlUri(sessionId, '/input/drag_path');
    if (controlUri == null) return false;
    return _postControl(controlUri, <String, dynamic>{
      'points': points,
    });
  }

  Future<bool> sendRemoteTextInput(String sessionId, String text) async {
    final controlUri = _resolveControlUri(sessionId, '/input/text');
    if (controlUri == null) return false;
    return _postControl(controlUri, <String, String>{'text': text});
  }

  Future<bool> sendRemoteQuality(String sessionId, double quality) async {
    final controlUri = _resolveControlUri(sessionId, '/settings/quality');
    if (controlUri == null) return false;
    return _postControl(controlUri, <String, dynamic>{'quality': quality});
  }

  Future<bool> sendRemoteClipboard(String sessionId, String text) async {
    final controlUri = _resolveControlUri(sessionId, '/clipboard/set');
    if (controlUri == null) return false;
    return _postControl(controlUri, <String, String>{'text': text});
  }

  Future<List<String>> fetchRemoteDisplays(String sessionId) async {
    final controlUri = _resolveControlUri(sessionId, '/displays');
    if (controlUri == null) return ['主显示器'];
    try {
      final request = await _getControlClient.getUrl(controlUri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return ['主显示器'];
      }
      final body = await utf8.decoder.bind(response).join();
      final list = jsonDecode(body) as List<dynamic>;
      return list
          .map((d) => (d as Map<String, dynamic>)['name'] as String? ?? '显示器')
          .toList();
    } catch (_) {
      return ['主显示器'];
    }
  }

  Future<String?> fetchRemoteClipboard(String sessionId) async {
    final controlUri = _resolveControlUri(sessionId, '/clipboard/get');
    if (controlUri == null) return null;
    try {
      final request = await _getControlClient.getUrl(controlUri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      final body = await utf8.decoder.bind(response).join();
      final payload = jsonDecode(body) as Map<String, dynamic>;
      return payload['text'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Synchronous URI resolution — no async I/O, just map lookup.
  /// Includes session_token query parameter when available.
  Uri? _resolveControlUri(String sessionId, String path) {
    final target = _sessionPreviewEndpoints[sessionId];
    if (target == null) {
      debugPrint(
          '[RDesk] _resolveControlUri: no endpoint for session $sessionId');
      return null;
    }
    final sessionToken = _sessionTokens[sessionId];
    if (sessionToken != null) {
      return target.replace(
        path: path,
        queryParameters: {
          ...target.queryParameters,
          'session_token': sessionToken,
        },
      );
    }
    return target.replace(path: path);
  }

  Future<void> _saveConnectionHistory(List<ConnectionRecord> records) async {
    final prefs = await _prefs;
    final payload = records
        .map(
          (record) => <String, dynamic>{
            'peerId': record.peerId,
            'peerHostname': record.peerHostname,
            'peerOs': record.peerOs,
            'connectedAt': record.connectedAt.toIso8601String(),
            'disconnectedAt': record.disconnectedAt?.toIso8601String(),
            'connectionType': record.connectionType,
            'status': record.status,
            'failureReason': record.failureReason,
          },
        )
        .toList();
    await prefs.setString(_connectionsKey, jsonEncode(payload));
  }

  Future<void> _saveChatMessages(
      String sessionId, List<ChatMessage> messages) async {
    final prefs = await _prefs;
    final payload = messages
        .map(
          (message) => <String, dynamic>{
            'sender': message.sender,
            'content': message.content,
            'timestamp': message.timestamp.toIso8601String(),
            'isLocal': message.isLocal,
          },
        )
        .toList();
    await prefs.setString('$_chatPrefix$sessionId', jsonEncode(payload));
  }

  String _generateDigits(int length) {
    final random = Random.secure();
    final first = random.nextInt(9) + 1;
    final rest = List.generate(length - 1, (_) => random.nextInt(10)).join();
    return '$first$rest';
  }

  String _generateAlphaNumeric(int length) {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(
        length, (_) => alphabet[random.nextInt(alphabet.length)]).join();
  }

  Future<RemoteFrameData?> _fetchRemotePreviewFrame(
    String sessionId, {
    Uri? endpoint,
  }) async {
    if (endpoint == null) return null;

    final stopwatch = Stopwatch()..start();
    try {
      // Include session token for authenticated LAN endpoints.
      final sessionToken = _sessionTokens[sessionId];
      final authedEndpoint = sessionToken != null
          ? endpoint.replace(queryParameters: {
              ...endpoint.queryParameters,
              'session_token': sessionToken,
            })
          : endpoint;
      final request = await _getFrameClient.getUrl(authedEndpoint);
      final response = await request.close();
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        _terminatedSessions.add(sessionId);
        _sessionPreviewEndpoints.remove(sessionId);
        await response.drain<void>();
        return null;
      }
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }

      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      stopwatch.stop();

      final bytes = builder.takeBytes();
      if (bytes.isEmpty) {
        return null;
      }
      if (!_looksLikeSupportedImage(bytes)) {
        return null;
      }

      final width =
          int.tryParse(response.headers.value('x-rdesk-width') ?? '') ?? 0;
      final height =
          int.tryParse(response.headers.value('x-rdesk-height') ?? '') ?? 0;
      final detectedDims = _detectImageDimensions(bytes);
      final safeWidth = width > 0 ? width : (detectedDims?.$1 ?? 0);
      final safeHeight = height > 0 ? height : (detectedDims?.$2 ?? 0);

      return RemoteFrameData(
        bytes: bytes,
        width: safeWidth,
        height: safeHeight,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } on SocketException {
      // Connection refused / reset — the host has closed the LAN relay.
      // Treat as session termination so the viewer exits promptly.
      _terminatedSessions.add(sessionId);
      _sessionPreviewEndpoints.remove(sessionId);
      return null;
    } catch (_) {
      return null;
    }
  }

  RemoteFrameData? _decodeRemoteFramePacket(
    Uint8List packet, {
    int? receivedAtMs,
    int Function(int rawLatencyMs)? normalizeLatency,
  }) {
    if (packet.isEmpty) return null;
    final nowMs = receivedAtMs ?? DateTime.now().millisecondsSinceEpoch;

    // Preferred format: 16-byte header + encoded image bytes.
    if (packet.length >= 16) {
      final width =
          ByteData.sublistView(packet, 0, 4).getUint32(0, Endian.little);
      final height =
          ByteData.sublistView(packet, 4, 8).getUint32(0, Endian.little);
      final timestampMs =
          ByteData.sublistView(packet, 8, 16).getUint64(0, Endian.little);
      final payload = packet.sublist(16);
      if (_looksLikeSupportedImage(payload)) {
        final dims = _detectImageDimensions(payload);
        final safeWidth = _sanitizeFrameDimension(
          width.toInt(),
          fallback: dims?.$1 ?? 0,
        );
        final safeHeight = _sanitizeFrameDimension(
          height.toInt(),
          fallback: dims?.$2 ?? 0,
        );
        final rawLatency = nowMs - timestampMs.toInt();
        final latency = normalizeLatency?.call(rawLatency) ?? rawLatency;
        return RemoteFrameData(
          bytes: payload,
          width: safeWidth,
          height: safeHeight,
          latencyMs: latency.clamp(0, 9999),
        );
      }
    }

    // Compatibility fallback: legacy packet with raw image bytes only.
    if (_looksLikeSupportedImage(packet)) {
      final dims = _detectImageDimensions(packet);
      return RemoteFrameData(
        bytes: packet,
        width: dims?.$1 ?? 0,
        height: dims?.$2 ?? 0,
        latencyMs: 0,
      );
    }
    return null;
  }

  int _sanitizeFrameDimension(int value, {required int fallback}) {
    if (value > 0 && value <= 16384) return value;
    if (fallback > 0 && fallback <= 16384) return fallback;
    return 0;
  }

  bool _looksLikeSupportedImage(Uint8List bytes) {
    if (bytes.length < 4) return false;
    // JPEG
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return true;
    }
    // PNG
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return true;
    }
    // WEBP
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    return false;
  }

  (int, int)? _detectImageDimensions(Uint8List bytes) {
    final jpeg = _readJpegDimensions(bytes);
    if (jpeg != null) return jpeg;
    final png = _readPngDimensions(bytes);
    if (png != null) return png;
    return null;
  }

  (int, int)? _readJpegDimensions(Uint8List data) {
    if (data.length < 10 || data[0] != 0xFF || data[1] != 0xD8) {
      return null;
    }
    for (var i = 0; i < data.length - 9; i++) {
      if (data[i] == 0xFF && (data[i + 1] == 0xC0 || data[i + 1] == 0xC2)) {
        final height = (data[i + 5] << 8) | data[i + 6];
        final width = (data[i + 7] << 8) | data[i + 8];
        if (width > 0 && height > 0) {
          return (width, height);
        }
      }
    }
    return null;
  }

  (int, int)? _readPngDimensions(Uint8List data) {
    if (data.length < 24) return null;
    final isPng = data[0] == 0x89 &&
        data[1] == 0x50 &&
        data[2] == 0x4E &&
        data[3] == 0x47 &&
        data[4] == 0x0D &&
        data[5] == 0x0A &&
        data[6] == 0x1A &&
        data[7] == 0x0A;
    if (!isPng) return null;
    final width = ByteData.sublistView(data, 16, 20).getUint32(0, Endian.big);
    final height = ByteData.sublistView(data, 20, 24).getUint32(0, Endian.big);
    if (width > 0 && height > 0) {
      return (width.toInt(), height.toInt());
    }
    return null;
  }

  Uri _normalizeFrameUri(String endpoint) {
    final base =
        endpoint.startsWith('http://') || endpoint.startsWith('https://')
            ? Uri.parse(endpoint)
            : Uri.parse('http://$endpoint');
    if (base.path.isEmpty || base.path == '/') {
      return base.replace(path: '/frame.jpg');
    }
    return base;
  }

  Uri _normalizeApiBaseUri(String endpoint) {
    if (endpoint.isEmpty) {
      return Uri.parse('http://${AppConstants.defaultSignalingServer}');
    }
    if (endpoint.startsWith('http://') || endpoint.startsWith('https://')) {
      return Uri.parse(endpoint);
    }
    return Uri.parse('http://$endpoint');
  }

  Future<Map<String, dynamic>> _postJson({
    required String path,
    required Map<String, Object?> body,
    String? bearerToken,
  }) async {
    final settings = await loadSettings();
    final apiBase = _normalizeApiBaseUri(settings.signalingServer.trim());
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);

    try {
      final request = await client.postUrl(apiBase.replace(path: path));
      request.headers.contentType = ContentType.json;
      if (bearerToken != null && bearerToken.isNotEmpty) {
        request.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
      }
      request.write(jsonEncode(body));
      final response = await request.close();
      final raw = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        throw Exception(_extractApiMessage(raw, fallback: '请求失败'));
      }
      if (raw.isEmpty) {
        return const <String, dynamic>{};
      }
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } on HandshakeException catch (e) {
      throw Exception(
        '无法建立安全连接，请检查服务器地址或 HTTPS 证书 (${e.message})，当前地址: ${apiBase.toString()}',
      );
    } on SocketException catch (e) {
      final errno = e.osError?.errorCode;
      final osMessage = e.osError?.message;
      final details = <String>[
        if (e.address != null) 'address=${e.address!.address}',
        if (e.port != 0) 'port=${e.port}',
        if (errno != null) 'errno=$errno',
        if (osMessage != null && osMessage.isNotEmpty) osMessage,
      ].join(', ');
      throw Exception(
        '无法连接服务器，请确认服务器地址和端口可访问。当前地址: ${apiBase.toString()}'
        '${details.isEmpty ? '' : '（$details）'}',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _getJson({
    required String path,
    String? bearerToken,
  }) async {
    final settings = await loadSettings();
    final apiBase = _normalizeApiBaseUri(settings.signalingServer.trim());
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);

    try {
      final request = await client.getUrl(apiBase.replace(path: path));
      if (bearerToken != null && bearerToken.isNotEmpty) {
        request.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
      }
      final response = await request.close();
      final raw = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        throw Exception(_extractApiMessage(raw, fallback: '请求失败'));
      }
      if (raw.isEmpty) {
        return const <String, dynamic>{};
      }
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } on HandshakeException catch (e) {
      throw Exception(
        '无法建立安全连接，请检查服务器地址或 HTTPS 证书 (${e.message})，当前地址: ${apiBase.toString()}',
      );
    } on SocketException catch (e) {
      final errno = e.osError?.errorCode;
      final osMessage = e.osError?.message;
      final details = <String>[
        if (e.address != null) 'address=${e.address!.address}',
        if (e.port != 0) 'port=${e.port}',
        if (errno != null) 'errno=$errno',
        if (osMessage != null && osMessage.isNotEmpty) osMessage,
      ].join(', ');
      throw Exception(
        '无法连接服务器，请确认服务器地址和端口可访问。当前地址: ${apiBase.toString()}'
        '${details.isEmpty ? '' : '（$details）'}',
      );
    } finally {
      client.close(force: true);
    }
  }

  AccountSession _parseAccountSession(Map<String, dynamic> payload) {
    final token = payload['token'] as String? ?? '';
    final userId = payload['user_id'] as String? ?? '';
    final username = payload['username'] as String? ?? '';
    final displayName = payload['display_name'] as String? ?? username;
    if (token.isEmpty || userId.isEmpty || username.isEmpty) {
      throw Exception('账号响应不完整');
    }
    return AccountSession(
      token: token,
      userId: userId,
      username: username,
      displayName: displayName,
    );
  }

  String _extractApiMessage(String raw, {required String fallback}) {
    if (raw.isEmpty) {
      return fallback;
    }
    try {
      final payload = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return payload['message'] as String? ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<PreviewResolveResult> _resolvePreviewEndpoint(
    String deviceId, {
    required String password,
    required String requesterId,
    String? requesterHostname,
    String? requesterPeerOs,
  }) async {
    final settings = await loadSettings();
    final apiBase = _normalizeApiBaseUri(settings.signalingServer.trim());
    // Passwordless requests need a longer timeout because the server waits
    // for the host to accept/reject (up to 60 seconds).
    final timeout = password.isEmpty
        ? const Duration(seconds: 65)
        : const Duration(seconds: 3);
    final client = HttpClient()..connectionTimeout = timeout;
    final authToken = await getAccountToken();

    try {
      final request = await client.postUrl(
        apiBase.replace(path: '/api/preview/resolve/$deviceId'),
      );
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode(<String, String?>{
          'password_hash':
              password.isEmpty ? null : _hashAccessSecret(password),
          'requester_id': requesterId,
          'auth_token': authToken,
          'requester_hostname': requesterHostname,
          'requester_peer_os': requesterPeerOs,
        }),
      );
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        return const PreviewResolveResult(
          found: false,
          authorized: false,
          endpoint: null,
          platform: null,
          hostname: null,
        );
      }
      final body = await utf8.decoder.bind(response).join();
      final payload = jsonDecode(body) as Map<String, dynamic>;
      final found = payload['found'] == true;
      final authorized = payload['authorized'] == true;
      final endpoint = payload['endpoint'] as String?;
      return PreviewResolveResult(
        found: found,
        authorized: authorized,
        endpoint: found && authorized && endpoint != null && endpoint.isNotEmpty
            ? _normalizeFrameUri(endpoint)
            : null,
        platform: payload['platform'] as String?,
        hostname: payload['hostname'] as String?,
      );
    } on TimeoutException {
      throw Exception('连接超时：服务器未及时响应，请检查网络或稍后重试');
    } on HandshakeException catch (e) {
      throw Exception(
        '无法建立安全连接，请检查服务器地址或 HTTPS 证书 (${e.message})，当前地址: ${apiBase.toString()}',
      );
    } on SocketException catch (e) {
      final errno = e.osError?.errorCode;
      final osMessage = e.osError?.message;
      final details = <String>[
        if (e.address != null) 'address=${e.address!.address}',
        if (e.port != 0) 'port=${e.port}',
        if (errno != null) 'errno=$errno',
        if (osMessage != null && osMessage.isNotEmpty) osMessage,
      ].join(', ');
      throw Exception(
        '无法连接服务器，请确认服务器地址和端口可访问。当前地址: ${apiBase.toString()}'
        '${details.isEmpty ? '' : '（$details）'}',
      );
    } catch (_) {
      return const PreviewResolveResult(
        found: false,
        authorized: false,
        endpoint: null,
        platform: null,
        hostname: null,
      );
    } finally {
      client.close(force: true);
    }
  }

  String _hashAccessSecret(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  Future<void> _trustViewerOnRemote({
    required String sessionId,
    required DeviceInfo requester,
    String? password,
  }) async {
    final trustUri = _resolveControlUri(sessionId, '/session/trust');
    if (trustUri == null) return;
    try {
      final request = await _getControlClient.postUrl(trustUri);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode(<String, dynamic>{
          'deviceId': requester.deviceId,
          'hostname': requester.hostname,
          'peerOs': requester.os,
          if (password != null) 'password': password,
        }),
      );
      final response = await request.close();
      if (response.statusCode == HttpStatus.ok) {
        final body = await utf8.decoder.bind(response).join();
        final payload = jsonDecode(body) as Map<String, dynamic>;
        final sessionToken = payload['session_token'] as String?;
        if (sessionToken != null && sessionToken.isNotEmpty) {
          _sessionTokens[sessionId] = sessionToken;
        }
      } else {
        await response.drain<void>();
      }
    } catch (_) {
      // Trust sync is best-effort for MVP flows.
    }
  }

  Future<RemoteFrameData> _renderDemoFrame({
    required String sessionId,
    required String peerId,
    required int tick,
  }) async {
    const width = 1280;
    const height = 720;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final rect = ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    final progress = (tick % 180) / 180;
    final latency = 36 + ((sin(tick / 4) + 1) * 12).round();

    canvas.drawRect(
      rect,
      ui.Paint()
        ..shader = ui.Gradient.linear(
          const ui.Offset(0, 0),
          ui.Offset(width.toDouble(), height.toDouble()),
          const [
            ui.Color(0xFF09111F),
            ui.Color(0xFF0F2A52),
            ui.Color(0xFF081426),
          ],
        ),
    );

    final glowPaint = ui.Paint()
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 90);
    glowPaint.color = const ui.Color(0x661E88E5);
    canvas.drawCircle(
      ui.Offset(width * (0.18 + progress * 0.18), height * 0.26),
      120,
      glowPaint,
    );
    glowPaint.color = const ui.Color(0x3326C6DA);
    canvas.drawCircle(
      ui.Offset(width * (0.78 - progress * 0.12), height * 0.72),
      160,
      glowPaint,
    );

    final gridPaint = ui.Paint()
      ..color = const ui.Color(0x18FFFFFF)
      ..strokeWidth = 1;
    for (var x = 0; x <= width; x += 64) {
      canvas.drawLine(
        ui.Offset(x.toDouble(), 0),
        ui.Offset(x.toDouble(), height.toDouble()),
        gridPaint,
      );
    }
    for (var y = 0; y <= height; y += 64) {
      canvas.drawLine(
        ui.Offset(0, y.toDouble()),
        ui.Offset(width.toDouble(), y.toDouble()),
        gridPaint,
      );
    }

    final accentPaint = ui.Paint()
      ..color = const ui.Color(0xFF28C6E5)
      ..strokeWidth = 4
      ..style = ui.PaintingStyle.stroke;
    final chart = ui.Path()
      ..moveTo(110, 530)
      ..cubicTo(220, 470, 290, 580, 380, 520)
      ..cubicTo(470, 450, 540, 560, 640, 480)
      ..cubicTo(730, 410, 830, 520, 920, 430)
      ..cubicTo(1000, 360, 1100, 420, 1180, 320);
    canvas.drawPath(chart, accentPaint);

    _drawParagraph(
      canvas,
      'RDesk 实时预览流',
      const ui.Offset(88, 84),
      fontSize: 34,
      color: const ui.Color(0xFFFFFFFF),
      maxWidth: 420,
    );
    _drawParagraph(
      canvas,
      '当前链路仍是演示帧通道，用于验证客户端显示、刷新率和布局稳定性。',
      const ui.Offset(88, 132),
      fontSize: 18,
      color: const ui.Color(0xCCFFFFFF),
      maxWidth: 640,
    );

    _drawBadge(canvas, const ui.Offset(88, 216), '设备 $peerId');
    _drawBadge(
      canvas,
      const ui.Offset(252, 216),
      '会话 ${sessionId.substring(0, min(18, sessionId.length))}',
    );
    _drawBadge(canvas, const ui.Offset(552, 216), '延迟 ${latency}ms');

    _drawParagraph(
      canvas,
      '帧序号 ${tick + 1}',
      const ui.Offset(88, 308),
      fontSize: 52,
      color: const ui.Color(0xFFFFFFFF),
      maxWidth: 240,
    );
    _drawParagraph(
      canvas,
      '分辨率 1280 x 720',
      const ui.Offset(88, 374),
      fontSize: 20,
      color: const ui.Color(0xCCFFFFFF),
      maxWidth: 260,
    );
    _drawParagraph(
      canvas,
      '时间 ${DateTime.now().toLocal().toIso8601String().substring(11, 19)}',
      const ui.Offset(88, 408),
      fontSize: 20,
      color: const ui.Color(0xCCFFFFFF),
      maxWidth: 300,
    );

    final scanPaint = ui.Paint()..color = const ui.Color(0x33FFFFFF);
    final scanY = 470 + sin(tick / 5) * 90;
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(84, scanY, width - 168, 2),
        const ui.Radius.circular(2),
      ),
      scanPaint,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    if (byteData == null) {
      return RemoteFrameData(
        bytes: Uint8List(0),
        width: width,
        height: height,
        latencyMs: 42,
      );
    }

    return RemoteFrameData(
      bytes: byteData.buffer.asUint8List(),
      width: width,
      height: height,
      latencyMs: latency,
    );
  }

  void _drawParagraph(
    ui.Canvas canvas,
    String text,
    ui.Offset offset, {
    required double fontSize,
    required ui.Color color,
    required double maxWidth,
  }) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: fontSize, maxLines: 2),
    )..pushStyle(ui.TextStyle(color: color));
    builder.addText(text);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: maxWidth));
    canvas.drawParagraph(paragraph, offset);
  }

  void _drawBadge(ui.Canvas canvas, ui.Offset offset, String text) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: 16, maxLines: 1),
    )..pushStyle(ui.TextStyle(color: const ui.Color(0xFFF4F8FF)));
    builder.addText(text);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 260));

    final badgeRect = ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(
        offset.dx - 12,
        offset.dy - 8,
        paragraph.maxIntrinsicWidth + 24,
        40,
      ),
      const ui.Radius.circular(18),
    );

    canvas.drawRRect(
      badgeRect,
      ui.Paint()..color = const ui.Color(0x1FFFFFFF),
    );
    canvas.drawRRect(
      badgeRect,
      ui.Paint()
        ..color = const ui.Color(0x3A48C2FF)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawParagraph(paragraph, offset);
  }
}
