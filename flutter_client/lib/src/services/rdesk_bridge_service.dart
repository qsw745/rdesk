import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';
import '../models/connection_info.dart';
import '../models/device.dart';
import '../models/file_entry.dart';
import '../utils/constants.dart';

class BridgeSettingsData {
  final String signalingServer;
  final String relayServer;
  final bool autoAccept;
  final String theme;
  final String? permanentPassword;

  const BridgeSettingsData({
    required this.signalingServer,
    required this.relayServer,
    required this.autoAccept,
    required this.theme,
    required this.permanentPassword,
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
  static const _themeKey = 'rdesk.theme';
  static const _permanentPasswordKey = 'rdesk.permanent_password';
  static const _chatPrefix = 'rdesk.chat.';

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
    if (password.isEmpty) {
      throw Exception('请输入连接密码');
    }

    await Future<void>.delayed(const Duration(milliseconds: 550));
    final sessionId = 'session-${DateTime.now().millisecondsSinceEpoch}';
    final records = await listConnectionHistory();
    final updated = <ConnectionRecord>[
      ConnectionRecord(
        peerId: deviceId,
        peerHostname: '远程设备 $deviceId',
        peerOs: '未知系统',
        connectedAt: DateTime.now(),
        connectionType: 'p2p',
      ),
      ...records,
    ];
    await _saveConnectionHistory(updated.take(12).toList());
    return sessionId;
  }

  Future<void> disconnect(String sessionId) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  Future<List<ConnectionRecord>> listConnectionHistory() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_connectionsKey);
    if (raw == null || raw.isEmpty) return [];
    final data = (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
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
          ),
        )
        .toList();
  }

  Future<BridgeSettingsData> loadSettings() async {
    final prefs = await _prefs;
    return BridgeSettingsData(
      signalingServer: prefs.getString(_signalingServerKey) ??
          AppConstants.defaultSignalingServer,
      relayServer:
          prefs.getString(_relayServerKey) ?? AppConstants.defaultRelayServer,
      autoAccept: prefs.getBool(_autoAcceptKey) ?? false,
      theme: prefs.getString(_themeKey) ?? 'system',
      permanentPassword: prefs.getString(_permanentPasswordKey),
    );
  }

  Future<void> saveSettings({
    String? signalingServer,
    String? relayServer,
    bool? autoAccept,
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
    if (theme != null) {
      await prefs.setString(_themeKey, theme);
    }
  }

  Future<void> setPermanentPassword(String? password) async {
    final prefs = await _prefs;
    if (password == null || password.isEmpty) {
      await prefs.remove(_permanentPasswordKey);
      return;
    }
    await prefs.setString(_permanentPasswordKey, password);
  }

  Future<List<ChatMessage>> listChatMessages(String sessionId) async {
    final prefs = await _prefs;
    final raw = prefs.getString('$_chatPrefix$sessionId');
    if (raw == null || raw.isEmpty) return [];
    final data = (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
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

  Future<List<FileEntry>> listRemoteDirectory(String sessionId, String path) async {
    // Bridge bindings are not generated yet. Reuse local listing as a
    // deterministic placeholder so the UI is fully functional.
    return listLocalDirectory(path);
  }

  Future<void> uploadFile(String sessionId, String localPath, String remotePath) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  Future<void> downloadFile(String sessionId, String remotePath, String localPath) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
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
          },
        )
        .toList();
    await prefs.setString(_connectionsKey, jsonEncode(payload));
  }

  Future<void> _saveChatMessages(String sessionId, List<ChatMessage> messages) async {
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
    return List.generate(length, (_) => alphabet[random.nextInt(alphabet.length)]).join();
  }
}
