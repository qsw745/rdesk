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
