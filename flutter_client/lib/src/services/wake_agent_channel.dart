import 'dart:io';
import 'dart:async';
import 'desktop_wake_agent.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class WakeAgentStatus {
  final bool enabled, networkReady;
  final String? agentId, endpoint, ownerId, errorCode;
  const WakeAgentStatus(
      {this.enabled = false,
      this.networkReady = false,
      this.agentId,
      this.endpoint,
      this.ownerId,
      this.errorCode});
  factory WakeAgentStatus.fromMap(Map<dynamic, dynamic> m) => WakeAgentStatus(
      enabled: m['enabled'] == true,
      networkReady: m['networkReady'] == true,
      agentId: m['agentId'] as String?,
      endpoint: m['endpoint'] as String?,
      ownerId: m['ownerId'] as String?,
      errorCode: m['errorCode'] as String?);
}

class WakeAgentChannel {
  int _generation = 0;
  final desktop = DesktopWakeAgent();
  static const _channel = MethodChannel('com.qsw.rdesk/wake_agent');
  Future<WakeAgentStatus> status() async => Platform.isAndroid
      ? WakeAgentStatus.fromMap(await _channel.invokeMapMethod('status') ?? {})
      : Platform.isMacOS
          ? WakeAgentStatus(
              enabled: desktop.enabled,
              networkReady: desktop.ready,
              agentId: desktop.agentId,
              endpoint: desktop.endpoint,
              ownerId: desktop.owner,
              errorCode: desktop.error)
          : const WakeAgentStatus();

  /// LAN the Mac helper relays on; remembered so a restart resumes only there.
  Map<String, String>? get resumeNetwork =>
      Platform.isMacOS ? desktop.selected?.config : null;

  /// Selects the remembered LAN again when the same interface, hardware
  /// address and IPv4 CIDR are present now. Never falls back to another LAN.
  Future<bool> selectResumeNetwork(Map<String, dynamic> saved) async {
    if (!Platform.isMacOS) return false;
    for (final network in await desktop.networks()) {
      final config = network.config;
      if (config.keys.every((k) => config[k] == saved[k])) {
        desktop.selected = network;
        return true;
      }
    }
    return false;
  }

  Future<void> prepare() async {
    if (Platform.isMacOS) {
      if (desktop.selected == null) throw StateError('请先选择家庭网络');
      return;
    }
    if (!Platform.isAndroid) throw StateError('请在家中的安卓手机或 Mac 启用助手');
    if (!await Permission.notification.request().isGranted) {
      throw StateError('请允许通知，以便查看助手状态和随时停止');
    }
  }

  Future<void> start(
      {required String endpoint,
      required String ownerId,
      required String agentId,
      required String token}) async {
    if (Platform.isMacOS) {
      await desktop.start(
          endpoint: endpoint, ownerId: ownerId, agentId: agentId, token: token);
      return;
    }
    final gen = _generation;
    await _channel.invokeMethod('start', {
      'endpoint': endpoint,
      'ownerId': ownerId,
      'agentId': agentId,
      'token': token
    });
    for (var attempt = 0; attempt < 20; attempt++) {
      if (gen != _generation) throw StateError('助手启动已取消');
      final current = await status();
      if (gen != _generation) throw StateError('助手启动已取消');
      if (current.enabled && current.agentId == agentId) return;
      if (current.errorCode != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await stop();
    throw StateError('助手未能启动，请检查通知权限、Wi-Fi 和后台限制');
  }

  Future<void> stop() async {
    ++_generation;
    if (Platform.isMacOS) await desktop.stop();
    if (Platform.isAndroid) await _channel.invokeMethod('stop');
  }

  Future<void> openBatterySettings() async {
    if (Platform.isAndroid) await _channel.invokeMethod('openBatterySettings');
  }
}

/// Turns helper status codes from Android and the Mac helper into guidance.
String describeHelperError(String code) => switch (code) {
      'network_paused' => '已离开家庭 Wi-Fi，回到同一网络后自动继续',
      'wifi_required' => '请先连接电脑所在的家庭 Wi-Fi',
      'ipv4_required' => '当前 Wi-Fi 没有唯一的局域网 IPv4 地址，请检查路由器设置',
      'network_changed' => '家庭网络与启用时不同，请回到原网络后重新启用',
      'configuration_missing' => '助手配置已丢失，请重新启用',
      'network' => '暂时连不上服务器，正在自动重试',
      'start_failed' => '助手启动失败，请重试',
      'unauthorized' || 'forbidden' || 'not_found' => '助手授权已失效或已被移除，请重新启用',
      'expired' || 'conflict' => '上一条开机请求已过期或被取消，助手继续待命',
      'rate_limited' => '请求过于频繁，稍后自动重试',
      'storage' => '服务器暂时无法保存，稍后自动重试',
      _ =>
        code.contains(RegExp(r'[\u4e00-\u9fff]')) ? code : '助手异常（$code），请重新启用',
    };
