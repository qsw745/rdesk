import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rdesk/src/services/rdesk_bridge_service.dart';

/// 连接历史里同一台设备只应保留一条。
///
/// 此前每次连接都追加一条记录，连接页「设备代码」下拉于是列出一串完全相同的
/// 代码；更糟的是 12 条上限被同一台设备占满后，别的设备再也不会出现在建议里。
void main() {
  const historyKey = 'rdesk.connection_logs';

  Map<String, dynamic> record(String peerId, String connectedAt) => {
        'peerId': peerId,
        'peerHostname': '设备 $peerId',
        'peerOs': 'android',
        'connectedAt': connectedAt,
        'disconnectedAt': null,
        'connectionType': 'preview-registry',
        'status': 'success',
        'failureReason': null,
      };

  test('同一设备的多条历史被折叠为最新的一条', () async {
    SharedPreferences.setMockInitialValues({
      historyKey: jsonEncode([
        record('660725198', '2026-08-12T10:00:00.000'),
        record('660725198', '2026-08-12T09:00:00.000'),
        record('660725198', '2026-08-12T08:00:00.000'),
      ]),
    });

    final history = await RdeskBridgeService.instance.listConnectionHistory();

    expect(history.length, 1);
    expect(history.single.peerId, '660725198');
    // 列表按新→旧排列，保留的必须是最新那条。
    expect(
        history.single.connectedAt, DateTime.parse('2026-08-12T10:00:00.000'));
  });

  test('不同设备各自保留，顺序不变', () async {
    SharedPreferences.setMockInitialValues({
      historyKey: jsonEncode([
        record('111111111', '2026-08-12T12:00:00.000'),
        record('222222222', '2026-08-12T11:00:00.000'),
        record('111111111', '2026-08-12T10:00:00.000'),
        record('333333333', '2026-08-12T09:00:00.000'),
      ]),
    });

    final history = await RdeskBridgeService.instance.listConnectionHistory();

    expect(
      history.map((r) => r.peerId).toList(),
      ['111111111', '222222222', '333333333'],
    );
  });

  test('重复记录不再挤占 12 条上限，其他设备仍可见', () async {
    SharedPreferences.setMockInitialValues({
      historyKey: jsonEncode([
        for (var i = 0; i < 12; i++)
          record('660725198',
              '2026-08-12T10:00:${i.toString().padLeft(2, '0')}.000'),
        record('999999999', '2026-08-11T10:00:00.000'),
      ]),
    });

    final history = await RdeskBridgeService.instance.listConnectionHistory();

    expect(history.length, 2);
    expect(
        history.map((r) => r.peerId), containsAll(['660725198', '999999999']));
  });

  test('空历史返回空列表', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await RdeskBridgeService.instance.listConnectionHistory(), isEmpty);
  });
}
