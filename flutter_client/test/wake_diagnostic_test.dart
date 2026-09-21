import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/models/wake.dart';
import 'package:rdesk/src/models/wake_diagnostic.dart';

void main() {
  const target = WakeTarget(
      id: 'private-target',
      name: '电脑',
      deviceId: 'private-device',
      mac: '02:11:22:33:44:55',
      agentId: 'helper',
      online: false,
      agentOnline: true,
      revision: 1);
  test('诊断区分发包和物理启动，导出不含设备敏感字段', () {
    const request = WakeRequest(
        id: 'request-1',
        targetId: 'private-target',
        phase: WakePhase.sent,
        createdAtMs: 1000,
        claimedAtMs: 2000,
        sentAtMs: 3000);
    final text = wakeDiagnosticReport(
        target: target,
        helper: const WakeAgent(
            id: 'h',
            name: '192.168.1.2 / 02:11:22:33:44:55',
            online: true,
            enabled: true),
        requests: [request],
        environment: '外网／蜂窝网络',
        observation: '尚未观察');
    expect(text, contains('request-1'));
    expect(text, contains('未自动验证'));
    expect(text, contains('应用上线：未收到'));
    expect(text, contains('不能单独证明'));
    for (final value in [
      target.mac,
      target.id,
      target.deviceId,
      '192.168.1.2'
    ]) {
      expect(text, isNot(contains(value)));
    }
  });
  test('超时提示登录界面，不断言硬件开机失败', () {
    const request = WakeRequest(
        id: 'r', targetId: 't', phase: WakePhase.unconfirmed, createdAtMs: 1);
    expect(wakeNextStep(request, true), contains('登录界面'));
    expect(wakeNextStep(null, false), contains('当前无法发送'));
  });
}
