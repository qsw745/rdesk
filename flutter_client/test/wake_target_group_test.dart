import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/models/wake.dart';
import 'package:rdesk/src/utils/wake_target_group.dart';

void main() {
  WakeTarget target(String id,
          {String? deviceId,
          String mac = '02:11:22:33:44:55',
          bool online = false,
          bool agentOnline = false,
          bool setupComplete = true,
          int? lastSeenMs}) =>
      WakeTarget(
          id: id,
          name: '同名电脑',
          deviceId: deviceId ?? 'device-$id',
          mac: mac,
          agentId: 'helper-$id',
          online: online,
          agentOnline: agentOnline,
          setupComplete: setupComplete,
          lastSeenMs: lastSeenMs,
          revision: 1);

  test('有效单播 MAC 大小写和分隔符统一，成员保留原始目标', () {
    final first = target('a', mac: '02:ab:cd:33:44:55');
    final second = target('b', mac: ' 02-AB-CD-33-44-55 ');
    expect(wakeTargetGroupKey(first), wakeTargetGroupKey(second));
    final groups = groupWakeTargets([first, second]);
    expect(groups, hasLength(1));
    expect(groups.single.members, containsAll([first, second]));
    expect(() => groups.single.members.clear(), throwsUnsupportedError);
  });

  test('不同 MAC 和非法、全零、组播 MAC 不跨目标合并', () {
    final groups = groupWakeTargets([
      target('a'),
      target('b', mac: '02:11:22:33:44:66'),
      target('c', mac: 'invalid'),
      target('d', mac: 'invalid'),
      target('e', mac: '00:00:00:00:00:00'),
      target('f', mac: '00:00:00:00:00:00'),
      target('g', mac: '01:11:22:33:44:55'),
      target('h', mac: '01:11:22:33:44:55')
    ]);
    expect(groups, hasLength(8));
    expect(wakeTargetGroupKey(target('bad', mac: 'invalid')), 'target:bad');
  });

  test('当前账号在线对应设备码优先于更旧或仅助手在线的目标', () {
    final old = target('old', agentOnline: true, lastSeenMs: 200);
    final current = target('current', deviceId: 'current-pc', lastSeenMs: 100);
    final group =
        groupWakeTargets([old, current], accountDeviceIds: {'current-pc'})
            .single;
    expect(group.primary, current);
  });

  test('目标专用心跳在线优先，其后按最近在线时间选择', () {
    final olderOnline = target('old', online: true, lastSeenMs: 100);
    final recentOnline = target('recent', online: true, lastSeenMs: 200);
    final offline = target('offline', agentOnline: true, lastSeenMs: 300);
    expect(
        groupWakeTargets([offline, olderOnline, recentOnline]).single.primary,
        recentOnline);
  });

  test('离线目标最近在线时间相同才优先当前有效助手', () {
    final recent = target('recent', lastSeenMs: 200);
    final useful = target('useful', agentOnline: true, lastSeenMs: 100);
    expect(groupWakeTargets([recent, useful]).single.primary, recent);
    final tied = target('tied', lastSeenMs: 100);
    expect(groupWakeTargets([tied, useful]).single.primary, useful);
  });

  test('完全相同证据按 ID 稳定选择，不受服务器列表顺序影响', () {
    final a = target('a'), b = target('b');
    expect(groupWakeTargets([a, b]).single.primary, a);
    expect(groupWakeTargets([b, a]).single.primary, a);
  });
}
