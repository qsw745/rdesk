import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class RdeskBridgeService {
  RdeskBridgeService._();

  static final RdeskBridgeService instance = RdeskBridgeService._();
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
  static const _chatPrefix = 'rdesk.chat.';
  final Map<String, Uri> _sessionPreviewEndpoints = <String, Uri>{};

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
      hostname: Platform.localHostname,
      version: AppConstants.version,
    );
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

    await Future<void>.delayed(const Duration(milliseconds: 550));
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
        throw Exception('请输入密码，或先在对端将本机设为受信设备');
      }
      throw Exception('连接密码错误');
    }

    final sessionId = 'session-${DateTime.now().millisecondsSinceEpoch}';
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

  Stream<RemoteFrameData?> watchSessionFrames(
    String sessionId, {
    required String peerId,
  }) async* {
    for (var tick = 0; true; tick++) {
      final remoteFrame = await _fetchRemotePreviewFrame(
        endpoint: _sessionPreviewEndpoints[sessionId],
      );
      if (remoteFrame != null) {
        yield remoteFrame;
      } else if (_sessionPreviewEndpoints.containsKey(sessionId)) {
        yield null;
      } else {
        yield await _renderDemoFrame(
          sessionId: sessionId,
          peerId: peerId,
          tick: tick,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }
  }

  Future<void> disconnect(String sessionId) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    _sessionPreviewEndpoints.remove(sessionId);
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
    return BridgeSettingsData(
      signalingServer: prefs.getString(_signalingServerKey) ??
          AppConstants.defaultSignalingServer,
      relayServer:
          prefs.getString(_relayServerKey) ?? AppConstants.defaultRelayServer,
      autoAccept: prefs.getBool(_autoAcceptKey) ?? false,
      autoClipboardSync: prefs.getBool(_autoClipboardSyncKey) ?? false,
      rememberTrustedPeers: prefs.getBool(_rememberTrustedPeersKey) ?? true,
      theme: prefs.getString(_themeKey) ?? 'system',
      permanentPassword: prefs.getString(_permanentPasswordKey),
    );
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
    final prefs = await _prefs;
    final raw = prefs.getString(_trustedPeersKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final data =
        (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    final match = data.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item?['deviceId'] == deviceId,
          orElse: () => null,
        );
    return match?['password'] as String?;
  }

  Future<void> rememberTrustedPeer({
    required String deviceId,
    required String password,
    required String hostname,
    required String peerOs,
  }) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_trustedPeersKey);
    final data = raw == null || raw.isEmpty
        ? <Map<String, dynamic>>[]
        : (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    final now = DateTime.now().toIso8601String();
    data.removeWhere((item) => item['deviceId'] == deviceId);
    data.insert(0, <String, dynamic>{
      'deviceId': deviceId,
      'password': password,
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
    final prefs = await _prefs;
    if (password == null || password.isEmpty) {
      await prefs.remove(_permanentPasswordKey);
      return;
    }
    await prefs.setString(_permanentPasswordKey, password);
  }

  Future<String> getActiveAccessPassword() async {
    final settings = await loadSettings();
    final permanent = settings.permanentPassword?.trim();
    if (permanent != null && permanent.isNotEmpty) {
      return permanent;
    }
    return getTemporaryPassword();
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
    // Bridge bindings are not generated yet. Reuse local listing as a
    // deterministic placeholder so the UI is fully functional.
    return listLocalDirectory(path);
  }

  Future<void> uploadFile(
      String sessionId, String localPath, String remotePath) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  Future<void> downloadFile(
      String sessionId, String remotePath, String localPath) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  Future<void> registerPreviewHost({
    required String deviceId,
    required String endpoint,
    required String platform,
    required String hostname,
    required String password,
    required bool autoAccept,
    required List<String> trustedViewerIds,
  }) async {
    final settings = await loadSettings();
    final apiBase = _normalizeApiBaseUri(settings.signalingServer.trim());
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);

    try {
      final request =
          await client.postUrl(apiBase.replace(path: '/api/preview/register'));
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode(<String, Object>{
          'device_id': deviceId,
          'endpoint': endpoint,
          'platform': platform,
          'hostname': hostname,
          'password_hash': _hashAccessSecret(password),
          'auto_accept': autoAccept,
          'trusted_viewers': trustedViewerIds,
        }),
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('register failed: ${response.statusCode}',
            uri: apiBase);
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> unregisterPreviewHost(String deviceId) async {
    final settings = await loadSettings();
    final apiBase = _normalizeApiBaseUri(settings.signalingServer.trim());
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);

    try {
      final request = await client
          .postUrl(apiBase.replace(path: '/api/preview/unregister'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(<String, String>{'device_id': deviceId}));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('unregister failed: ${response.statusCode}',
            uri: apiBase);
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
    final localDevice = await getLocalDeviceInfo();
    final resolved = await _resolvePreviewEndpoint(
      deviceId,
      password: password,
      requesterId: localDevice.deviceId,
    );
    if (resolved.found && resolved.authorized && resolved.endpoint != null) {
      _sessionPreviewEndpoints[sessionId] = resolved.endpoint!;
    }
    return resolved;
  }

  Future<bool> sendRemoteTap(
    String sessionId, {
    required double normalizedX,
    required double normalizedY,
  }) async {
    final controlUri = await _resolveControlUri(sessionId, '/input/tap');
    if (controlUri == null) {
      return false;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.postUrl(controlUri);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode(<String, double>{
          'x': normalizedX.clamp(0, 1),
          'y': normalizedY.clamp(0, 1),
        }),
      );
      final response = await request.close();
      return response.statusCode == HttpStatus.ok;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> sendRemoteAction(String sessionId, String action) async {
    final controlUri = await _resolveControlUri(sessionId, '/input/action');
    if (controlUri == null) {
      return false;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.postUrl(controlUri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(<String, String>{'action': action}));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }
      final body = await utf8.decoder.bind(response).join();
      final payload = jsonDecode(body) as Map<String, dynamic>;
      return payload['ok'] == true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> sendRemoteLongPress(
    String sessionId, {
    required double normalizedX,
    required double normalizedY,
  }) async {
    final controlUri = await _resolveControlUri(sessionId, '/input/long_press');
    if (controlUri == null) {
      return false;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.postUrl(controlUri);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode(<String, double>{
          'x': normalizedX.clamp(0, 1),
          'y': normalizedY.clamp(0, 1),
        }),
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }
      final body = await utf8.decoder.bind(response).join();
      final payload = jsonDecode(body) as Map<String, dynamic>;
      return payload['ok'] == true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> sendRemoteDrag(
    String sessionId, {
    required double startX,
    required double startY,
    required double endX,
    required double endY,
  }) async {
    final controlUri = await _resolveControlUri(sessionId, '/input/drag');
    if (controlUri == null) {
      return false;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.postUrl(controlUri);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode(<String, double>{
          'startX': startX.clamp(0, 1),
          'startY': startY.clamp(0, 1),
          'endX': endX.clamp(0, 1),
          'endY': endY.clamp(0, 1),
        }),
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }
      final body = await utf8.decoder.bind(response).join();
      final payload = jsonDecode(body) as Map<String, dynamic>;
      return payload['ok'] == true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> sendRemoteTextInput(String sessionId, String text) async {
    final controlUri = await _resolveControlUri(sessionId, '/input/text');
    if (controlUri == null) {
      return false;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.postUrl(controlUri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(<String, String>{'text': text}));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }
      final body = await utf8.decoder.bind(response).join();
      final payload = jsonDecode(body) as Map<String, dynamic>;
      return payload['ok'] == true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> sendRemoteClipboard(String sessionId, String text) async {
    final controlUri = await _resolveControlUri(sessionId, '/clipboard/set');
    if (controlUri == null) {
      return false;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.postUrl(controlUri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(<String, String>{'text': text}));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }
      final body = await utf8.decoder.bind(response).join();
      final payload = jsonDecode(body) as Map<String, dynamic>;
      return payload['ok'] == true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> fetchRemoteClipboard(String sessionId) async {
    final controlUri = await _resolveControlUri(sessionId, '/clipboard/get');
    if (controlUri == null) {
      return null;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.getUrl(controlUri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }
      final body = await utf8.decoder.bind(response).join();
      final payload = jsonDecode(body) as Map<String, dynamic>;
      return payload['text'] as String?;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<Uri?> _resolveControlUri(String sessionId, String path) async {
    Uri? target = _sessionPreviewEndpoints[sessionId];
    if (target == null) {
      final settings = await loadSettings();
      final configured = settings.signalingServer.trim();
      if (configured.isEmpty ||
          configured == AppConstants.defaultSignalingServer) {
        return null;
      }
      target = _normalizeFrameUri(configured);
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

  Future<RemoteFrameData?> _fetchRemotePreviewFrame({
    Uri? endpoint,
  }) async {
    Uri? uri = endpoint;
    if (uri == null) {
      final settings = await loadSettings();
      final configured = settings.signalingServer.trim();
      if (configured.isEmpty ||
          configured == AppConstants.defaultSignalingServer) {
        return null;
      }
      uri = _normalizeFrameUri(configured);
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);

    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }

      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }

      final bytes = builder.takeBytes();
      if (bytes.isEmpty) {
        return null;
      }

      final width =
          int.tryParse(response.headers.value('x-rdesk-width') ?? '') ?? 0;
      final height =
          int.tryParse(response.headers.value('x-rdesk-height') ?? '') ?? 0;

      return RemoteFrameData(
        bytes: bytes,
        width: width,
        height: height,
        latencyMs: 48,
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
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
    return endpoint.startsWith('http://') || endpoint.startsWith('https://')
        ? Uri.parse(endpoint)
        : Uri.parse('http://$endpoint');
  }

  Future<PreviewResolveResult> _resolvePreviewEndpoint(
    String deviceId, {
    required String password,
    required String requesterId,
  }) async {
    final settings = await loadSettings();
    final apiBase = _normalizeApiBaseUri(settings.signalingServer.trim());
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);

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
        }),
      );
      final response = await request.close();
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
  }) async {
    final trustUri = await _resolveControlUri(sessionId, '/session/trust');
    if (trustUri == null) {
      return;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.postUrl(trustUri);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode(<String, String>{
          'deviceId': requester.deviceId,
          'hostname': requester.hostname,
          'peerOs': requester.os,
        }),
      );
      await request.close();
    } catch (_) {
      // Trust sync is best-effort for MVP flows.
    } finally {
      client.close(force: true);
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
