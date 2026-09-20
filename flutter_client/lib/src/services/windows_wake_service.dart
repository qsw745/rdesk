import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/wake.dart';
import 'wake_api.dart';
import 'windows_adapter_service.dart';
import 'windows_process_runner.dart';
export 'windows_adapter_service.dart';

enum WakeCheckState { enabled, disabled, unknown }

class WindowsWakeCheck {
  final WakeCheckState magicPacket, wakeArmed, shutdownWake;
  const WindowsWakeCheck(
      {required this.magicPacket,
      required this.wakeArmed,
      required this.shutdownWake});
  bool get allEnabled =>
      magicPacket == WakeCheckState.enabled &&
      wakeArmed == WakeCheckState.enabled &&
      shutdownWake == WakeCheckState.enabled;
  factory WindowsWakeCheck.fromJson(Map<String, dynamic> json) {
    WakeCheckState parse(Object? v) => v == true || v == 'Enabled' || v == '1'
        ? WakeCheckState.enabled
        : v == false || v == 'Disabled' || v == '0'
            ? WakeCheckState.disabled
            : WakeCheckState.unknown;
    return WindowsWakeCheck(
        magicPacket: parse(json['magicPacket']),
        wakeArmed: parse(json['wakeArmed']),
        shutdownWake: parse(json['shutdownWake']));
  }
}

class WindowsWakeService {
  final WakeApi _api;
  final WindowsAdapterService _adapters;
  final Future<ProcessResult> Function(String, List<String>)? _runOverride;
  final _processes = WindowsProcessRunner();
  Future<ProcessResult> _run(String exe, List<String> args) =>
      _runOverride?.call(exe, args) ?? _processes.run(exe, args);
  final FlutterSecureStorage _storage;
  Timer? _timer;
  WakeApi? _heartbeatApi;
  int _generation = 0;
  String? lastError;
  bool get active => _timer != null;
  WindowsWakeService(
      {required WakeApi api,
      Future<ProcessResult> Function(String, List<String>)? run,
      required FlutterSecureStorage storage,
      WindowsAdapterService adapters = const WindowsAdapterService()})
      : _api = api,
        _adapters = adapters,
        _runOverride = run,
        _storage = storage;

  /// Read driver settings only. BIOS and physical wake support require a real test.
  Future<WindowsWakeCheck> inspect(String mac) async {
    if (!RegExp(r'^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$').hasMatch(mac)) {
      throw const WakeApiException('invalid_mac', '请选择有效的有线网卡');
    }
    final script =
        r'''$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[System.Text.Encoding]::UTF8;
$nic=Get-NetAdapter -Physical | Where-Object { ($_.MacAddress -replace '-',':') -eq '__MAC__' } | Select-Object -First 1;
if (!$nic) { throw 'Adapter not found' }
$magic=$null; $armed=$null; $shutdown=$null;
try { $magic=($nic | Get-NetAdapterPowerManagement -ErrorAction Stop).WakeOnMagicPacket.ToString() } catch {}
try { $names=@(& powercfg.exe /devicequery wake_armed); if ($LASTEXITCODE -eq 0) { $armed=(@($names | ForEach-Object {$_.Trim()}) -contains $nic.InterfaceDescription) } } catch {}
try { $prop=$nic | Get-NetAdapterAdvancedProperty -AllProperties -ErrorAction Stop | Where-Object { $_.RegistryKeyword -in @('ShutdownWakeOnLan','S5WakeOnLan') } | Select-Object -First 1; if ($prop -and @($prop.RegistryValue).Count -eq 1) { $shutdown=[string]$prop.RegistryValue[0] } } catch {}
@{magicPacket=$magic; wakeArmed=$armed; shutdownWake=$shutdown} | ConvertTo-Json -Compress
'''
            .replaceAll('__MAC__', mac);
    final result = await _run('powershell.exe',
        ['-NoProfile', '-NonInteractive', '-Command', script]);
    if (result.exitCode != 0) {
      throw const WakeApiException('wake_check', '无法自动检测唤醒设置，请在设备管理器中核对');
    }
    return WindowsWakeCheck.fromJson(
        jsonDecode(result.stdout.toString().trim()) as Map<String, dynamic>);
  }

  Future<void> openDeviceManager() async {
    final result = await _run('cmd.exe', ['/c', 'start', '', 'devmgmt.msc']);
    if (result.exitCode != 0) {
      throw const WakeApiException('device_manager', '请在开始菜单打开设备管理器');
    }
  }

  /// Current-user startup only: no administrator task, service or login bypass.
  Future<void> setLoginStartup(bool enabled) async {
    final path = Platform.resolvedExecutable.replaceAll("'", "''");
    final script = enabled
        ? "New-Item -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run' -Force | Out-Null; Set-ItemProperty -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run' -Name 'RDesk' -Value '\"$path\"' -ErrorAction Stop"
        : "Remove-ItemProperty -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run' -Name 'RDesk' -ErrorAction SilentlyContinue";
    final result = await _run('powershell.exe',
        ['-NoProfile', '-NonInteractive', '-Command', script]);
    if (result.exitCode != 0) {
      throw const WakeApiException('startup', '设置登录后启动失败，请重试');
    }
  }

  Future<List<WindowsWakeAdapter>> adapters() => _adapters.adapters();
  Future<WindowsAdapterScan> scanAdapters() => _adapters.scan();

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
  Future<void> dispose() async {
    _stop();
    await _processes.dispose();
  }

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
