import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/models/account.dart';
import 'package:rdesk/src/models/address_book.dart';
import 'package:rdesk/src/models/connection_info.dart';
import 'package:rdesk/src/models/wake.dart';
import 'package:rdesk/src/utils/device_directory.dart';

void main() {
  final date = DateTime(2026, 9, 20);
  ConnectionRecord history(String id, {String? scope = 'https://a.test'}) =>
      ConnectionRecord(
          peerId: id,
          peerHostname: '家中电脑',
          peerOs: 'macos',
          connectedAt: date,
          connectionType: 'preview-registry',
          endpointScope: scope);
  WakeTarget wakeTarget(String id, String deviceId,
          {String mac = '02:11:22:33:44:55',
          bool online = false,
          bool agentOnline = false,
          int? lastSeenMs}) =>
      WakeTarget(
          id: id,
          name: 'Windows 电脑',
          deviceId: deviceId,
          mac: mac,
          agentId: 'helper-$id',
          online: online,
          agentOnline: agentOnline,
          lastSeenMs: lastSeenMs,
          revision: 1);
  test('同服务器多来源合并，收藏别名优先且历史不推导在线', () {
    final rows = mergeDeviceDirectory(
        endpointScope: 'https://a.test/',
        accountDevices: [],
        history: [
          history('pc'),
          history('pc')
        ],
        saved: [
          AddressBookEntry(
              deviceId: 'pc',
              alias: '我的 Mac',
              endpointScope: 'https://a.test:443',
              createdAt: date)
        ],
        wakeTargets: []);
    expect(rows.length, 1);
    expect(rows.single.name, '我的 Mac');
    expect(rows.single.favorite, true);
    expect(rows.single.online, false);
  });
  test('在线账号设备覆盖历史状态，不按名称合并', () {
    final rows =
        mergeDeviceDirectory(endpointScope: 'https://a.test', accountDevices: [
      AccountDevice(
          deviceId: 'pc',
          hostname: '家中电脑',
          platform: 'macos',
          updatedAtMs: date.millisecondsSinceEpoch)
    ], history: [
      history('pc'),
      history('other')
    ], saved: [], wakeTargets: []);
    expect(rows.length, 2);
    expect(rows.first.deviceId, 'pc');
    expect(rows.first.online, true);
    expect(rows.first.accountOwned, true);
    expect(rows.last.accountOwned, false);
  });
  test('不同服务器和无来源旧记录不能混成当前设备', () {
    final rows = mergeDeviceDirectory(
        endpointScope: 'https://a.test',
        accountDevices: [],
        history: [
          history('pc'),
          history('pc', scope: 'https://b.test'),
          history('pc', scope: null)
        ],
        saved: [],
        wakeTargets: []);
    expect(rows.length, 3);
    expect(rows.map((e) => e.key).toSet().length, 3);
    expect(rows.where((e) => e.endpointScope == null).length, 1);
  });
  test('独立开机电脑保留助手状态，不假装远控主机在线', () {
    final rows = mergeDeviceDirectory(
        endpointScope: 'https://a.test',
        accountDevices: [],
        history: [],
        saved: [],
        wakeTargets: [
          const WakeTarget(
              id: 'wake',
              name: 'Windows',
              deviceId: 'pc',
              mac: '02:11:22:33:44:55',
              agentId: 'home',
              online: false,
              agentOnline: true,
              revision: 1)
        ]);
    expect(rows.single.online, false);
    expect(rows.single.wakeTarget!.agentOnline, true);
    expect(rows.single.platform, 'windows');
  });
  test('登出或切换服务器后保留收藏且不能把历史标成在线', () {
    final rows = mergeDeviceDirectory(
        endpointScope: 'https://b.test',
        accountDevices: [],
        history: [history('pc')],
        saved: [AddressBookEntry(deviceId: 'pc', createdAt: date)],
        wakeTargets: []);
    expect(rows.length, 2);
    expect(rows.every((e) => !e.online), true);
    expect(rows.where((e) => e.favorite).length, 1);
  });
  test('旧收藏序列化仍保持来源未知', () {
    final entry =
        AddressBookEntry.fromJson({'deviceId': 'old', 'createdAt': 0});
    expect(entry.endpointScope, null);
    expect(entry.toJson().containsKey('endpointScope'), false);
  });

  test('官方旧 HTTP 来源归入 HTTPS，但不扩大到其他主机端口或未知来源', () {
    expect(normalizedEndpointScope('http://qisw.top'), 'https://qisw.top');
    expect(normalizedEndpointScope('http://qisw.top:80/'), 'https://qisw.top');
    expect(normalizedEndpointScope('http://qisw.top:21116/path'),
        'https://qisw.top');
    expect(normalizedEndpointScope('http://qisw.top:8080'),
        'http://qisw.top:8080');
    expect(normalizedEndpointScope('http://a.test'), 'http://a.test');
    expect(normalizedEndpointScope(null), isNull);
  });

  test('同 ID 官方旧 HTTP 历史收藏与当前账号在线状态合并', () {
    final rows = mergeDeviceDirectory(
        endpointScope: 'https://qisw.top',
        accountDevices: [
          AccountDevice(
              deviceId: 'pc',
              hostname: 'Mac',
              platform: 'macos',
              updatedAtMs: date.millisecondsSinceEpoch)
        ],
        history: [
          history('pc', scope: 'http://qisw.top:21116')
        ],
        saved: [
          AddressBookEntry(
              deviceId: 'pc',
              endpointScope: 'http://qisw.top',
              alias: '收藏 Mac',
              createdAt: date)
        ],
        wakeTargets: []);
    expect(rows, hasLength(1));
    expect(rows.single.name, '收藏 Mac');
    expect(rows.single.online, true);
    expect(rows.single.favorite, true);
    expect(rows.single.endpointScope, 'https://qisw.top');
  });

  test('同账号同 MAC 的开机目标聚合，最近心跳目标承接旧 ID 收藏历史', () {
    final rows = mergeDeviceDirectory(
        endpointScope: 'https://a.test',
        accountDevices: [],
        history: [
          history('old-pc')
        ],
        saved: [
          AddressBookEntry(
              deviceId: 'old-pc',
              endpointScope: 'https://a.test',
              alias: '书房电脑',
              createdAt: date)
        ],
        wakeTargets: [
          wakeTarget('old', 'old-pc', lastSeenMs: 10),
          wakeTarget('new', 'new-pc',
              mac: '02-11-22-33-44-55', agentOnline: true, lastSeenMs: 20)
        ]);
    expect(rows, hasLength(1));
    expect(rows.single.deviceId, 'new-pc');
    expect(rows.single.wakeTarget!.id, 'new');
    expect(rows.single.name, '书房电脑');
    expect(rows.single.favorite, true);
    expect(rows.single.lastSeen, date);
    expect(rows.single.relatedDeviceIds, ['new-pc', 'old-pc']);
    expect(rows.single.aliasKeys, ['https://a.test|old-pc']);
  });

  test('开机重复组优先选择当前账号在线的设备码', () {
    final rows =
        mergeDeviceDirectory(endpointScope: 'https://a.test', accountDevices: [
      AccountDevice(
          deviceId: 'current-pc',
          hostname: '当前电脑',
          platform: 'windows',
          updatedAtMs: date.millisecondsSinceEpoch)
    ], history: [], saved: [], wakeTargets: [
      wakeTarget('old', 'old-pc', agentOnline: true, lastSeenMs: 100),
      wakeTarget('current', 'current-pc', lastSeenMs: 10)
    ]);
    expect(rows, hasLength(1));
    expect(rows.single.deviceId, 'current-pc');
    expect(rows.single.wakeTarget!.id, 'current');
    expect(rows.single.online, true);
    expect(rows.single.accountOwned, true);
  });

  test('开机别名只用于当前服务器，不吸收外站和无来源记录', () {
    final rows = mergeDeviceDirectory(
        endpointScope: 'https://a.test',
        accountDevices: [],
        history: [
          history('old-pc', scope: null),
          history('old-pc', scope: 'https://b.test')
        ],
        saved: [],
        wakeTargets: [
          wakeTarget('old', 'old-pc', lastSeenMs: 10),
          wakeTarget('new', 'new-pc', lastSeenMs: 20)
        ]);
    expect(rows, hasLength(3));
    expect(rows.singleWhere((e) => e.endpointScope == null).wakeTarget, isNull);
    expect(
        rows.singleWhere((e) => e.endpointScope == 'https://b.test').wakeTarget,
        isNull);
    final current =
        rows.singleWhere((e) => e.endpointScope == 'https://a.test');
    expect(current.aliasKeys, ['https://a.test|old-pc']);
    expect(current.aliasKeys, isNot(contains('legacy|old-pc')));
    expect(current.aliasKeys, isNot(contains('https://b.test|old-pc')));
  });

  test('不同 MAC 与无效 MAC 不按同名聚合', () {
    final rows = mergeDeviceDirectory(
        endpointScope: 'https://a.test',
        accountDevices: [],
        history: [],
        saved: [],
        wakeTargets: [
          wakeTarget('a', 'pc-a'),
          wakeTarget('b', 'pc-b', mac: '02:11:22:33:44:66'),
          wakeTarget('c', 'pc-c', mac: 'invalid'),
          wakeTarget('d', 'pc-d', mac: 'invalid')
        ]);
    expect(rows, hasLength(4));
  });

  test('无来源的当前输入不能产生跨设备码的开机身份别名', () {
    final rows = mergeDeviceDirectory(
        endpointScope: '',
        accountDevices: [],
        history: [],
        saved: [],
        wakeTargets: [
          wakeTarget('old', 'old-pc', lastSeenMs: 10),
          wakeTarget('new', 'new-pc', lastSeenMs: 20)
        ]);
    expect(rows, hasLength(2));
    expect(rows.every((e) => e.aliasKeys.isEmpty), true);
  });
}
