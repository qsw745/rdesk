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
}
