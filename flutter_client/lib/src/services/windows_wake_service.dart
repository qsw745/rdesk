import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/wake.dart';
import 'wake_api.dart';

class WindowsWakeAdapter {
  final String id, name, mac;
  final bool connected, wired;
  const WindowsWakeAdapter(
      {required this.id,
      required this.name,
      required this.mac,
      required this.connected,
      required this.wired});
}

class WindowsWakeService {
  final WakeApi _api;
  final Future<ProcessResult> Function(String, List<String>) _run;
  final FlutterSecureStorage _storage;
  Timer? _timer;
  WakeApi? _heartbeatApi;
  int _generation = 0;
  String? lastError;
  bool get active => _timer != null;
  WindowsWakeService(
      {required WakeApi api,
      required Future<ProcessResult> Function(String, List<String>) run,
      required FlutterSecureStorage storage})
      : _api = api,
        _run = run,
        _storage = storage;
  Future<List<WindowsWakeAdapter>> adapters() async {
    const script =
        r'''$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[System.Text.Encoding]::UTF8; @(Get-NetAdapter -Physical | Select-Object @{n='InterfaceGuid';e={$_.InterfaceGuid.ToString()}},Name,MacAddress,@{n='Status';e={$_.Status.ToString()}},@{n='NdisPhysicalMedium';e={[int]$_.NdisPhysicalMedium}}) | ConvertTo-Json -Compress''';
    final result = await _run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      script
    ]).timeout(const Duration(seconds: 10));
    if (result.exitCode != 0) {
      throw const WakeApiException('adapter_query', '无法读取网卡，请检查 Windows 网络适配器');
    }
    final text = result.stdout.toString().trim();
    if (text.isEmpty) return [];
    final raw = jsonDecode(text);
    final rows = raw is List ? raw : [raw];
    final adapters = <WindowsWakeAdapter>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final mac = (row['MacAddress']?.toString() ?? '')
          .replaceAll('-', ':')
          .toUpperCase();
      if (!RegExp(r'^[0-9A-F]{2}(:[0-9A-F]{2}){5}$').hasMatch(mac) ||
          mac == '00:00:00:00:00:00' ||
          int.parse(mac.substring(0, 2), radix: 16).isOdd) {
        continue;
      }
      adapters.add(WindowsWakeAdapter(
          id: row['InterfaceGuid']?.toString() ?? mac,
          name: row['Name']?.toString() ?? '网卡',
          mac: mac,
          connected: row['Status'] == 'Up',
          wired: row['NdisPhysicalMedium'].toString() == '14'));
    }
    adapters.sort((a, b) => ((b.connected ? 2 : 0) + (b.wired ? 1 : 0))
        .compareTo((a.connected ? 2 : 0) + (a.wired ? 1 : 0)));
    return adapters;
  }

  String _key(String userId, Uri uri) {
    return 'rdesk.wake.windows.${sha256.convert(utf8.encode('$uri|$userId'))}';
  }

  Future<void> enroll(
      {required String userId,
      required String deviceId,
      required String name,
      required String agentId,
      required String mac}) async {
    _stop();
    final gen = _generation;
    final scoped = await _api.scoped();
    WakeEnrollment? enrollment;
    bool created = false;
    try {
      final key = _key(userId, await scoped.endpoint());
      final targets = await scoped.targets();
      if (gen != _generation) return;
      final matches = targets.where((t) => t.deviceId == deviceId);
      if (matches.isEmpty) {
        enrollment = await scoped.createTarget(
            name: name, deviceId: deviceId, mac: mac, agentId: agentId);
        created = true;
      } else {
        final id = matches.first.id;
        await scoped.updateTarget(id, name: name, mac: mac, agentId: agentId);
        enrollment = await scoped.rotateTargetToken(id);
      }
      if (gen != _generation) {
        if (created) {
          await scoped.deleteTarget(enrollment.id);
        } else {
          await scoped.rotateTargetToken(enrollment.id);
        }
        return;
      }
      try {
        await _storage.write(
            key: key,
            value:
                jsonEncode({'id': enrollment.id, 'token': enrollment.token}));
      } catch (_) {
        if (created) {
          await scoped.deleteTarget(enrollment.id);
        } else {
          await scoped.rotateTargetToken(enrollment.id);
        }
        rethrow;
      }
      if (gen != _generation) {
        await _storage.delete(key: key);
        return;
      }
      await resume(userId);
    } finally {
      scoped.close();
    }
  }

  Future<void> resume(String userId) async {
    _stop();
    final gen = _generation;
    final scoped = await _api.scoped();
    if (gen != _generation) {
      scoped.close();
      return;
    }
    final key = _key(userId, await scoped.endpoint());
    String? raw;
    try {
      raw = await _storage.read(key: key);
    } catch (_) {
      scoped.close();
      rethrow;
    }
    if (gen != _generation || raw == null) {
      scoped.close();
      return;
    }
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final enrollment = WakeEnrollment.fromJson(j);
    if (gen != _generation) {
      scoped.close();
      return;
    }
    _heartbeatApi = scoped;
    lastError = null;
    Future<void> beat() async {
      if (gen != _generation) return;
      try {
        await scoped.targetHeartbeat(enrollment.id, enrollment.token);
        if (gen == _generation) lastError = null;
      } on WakeApiException catch (e) {
        if (gen != _generation) return;
        lastError = e.message;
        if (e.statusCode == 401 || e.statusCode == 404) {
          await stop();
          return;
        }
      } catch (_) {
        if (gen == _generation) lastError = '电脑上线心跳暂时失败';
      }
      if (gen == _generation) {
        _timer = Timer(const Duration(seconds: 10), () => unawaited(beat()));
      }
    }

    await beat();
  }

  Future<void> stop() async => _stop();
  void _stop() {
    ++_generation;
    _timer?.cancel();
    _timer = null;
    _heartbeatApi?.close();
    _heartbeatApi = null;
  }

  Future<void> forget(String userId) async {
    await stop();
    await _storage.delete(key: _key(userId, await _api.endpoint()));
  }
}
