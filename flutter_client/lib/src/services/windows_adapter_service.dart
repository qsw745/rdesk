import 'dart:async';
import 'package:flutter/services.dart';
import 'wake_api.dart';

enum AdapterScanState { detecting, failed, disconnected, absent, detected }

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

class WindowsAdapterScan {
  final AdapterScanState state;
  final List<WindowsWakeAdapter> adapters;
  final String diagnostic;
  const WindowsAdapterScan(this.state, this.adapters, this.diagnostic);
  String get message => switch (state) {
        AdapterScanState.detecting => '正在检测有线网卡',
        AdapterScanState.failed => '网卡检测失败，请重试或复制诊断',
        AdapterScanState.disconnected => '已找到有线网卡，请连接网线',
        AdapterScanState.absent => '未发现物理有线网卡',
        AdapterScanState.detected => '已识别连接中的有线网卡',
      };
}

class WindowsAdapterService {
  final MethodChannel _channel;
  const WindowsAdapterService(
      {MethodChannel channel =
          const MethodChannel('com.qsw.rdesk/windows_wake')})
      : _channel = channel;

  Future<WindowsAdapterScan> scan() async {
    final clock = Stopwatch()..start();
    try {
      final raw = await _channel
          .invokeMapMethod<String, Object?>('listAdapters')
          .timeout(const Duration(seconds: 10));
      if (raw == null ||
          raw['schema'] != 1 ||
          raw['source'] != 'ip_helper' ||
          raw['adapters'] is! List) {
        throw const FormatException();
      }
      final adapters = <WindowsWakeAdapter>[];
      for (final item in raw['adapters'] as List) {
        if (item is! Map ||
            item['hardware'] is! bool ||
            item['connected'] is! bool ||
            item['if_type'] is! int ||
            item['id'] is! String ||
            item['name'] is! String ||
            item['mac'] is! String) {
          throw const FormatException();
        }
        if (item['hardware'] != true) continue;
        final mac = (item['mac'] as String).replaceAll('-', ':').toUpperCase();
        if (!RegExp(r'^[0-9A-F]{2}(:[0-9A-F]{2}){5}$').hasMatch(mac) ||
            mac == '00:00:00:00:00:00' ||
            int.parse(mac.substring(0, 2), radix: 16).isOdd) {
          continue;
        }
        adapters.add(WindowsWakeAdapter(
            id: item['id'] as String,
            name: item['name'] as String,
            mac: mac,
            connected: item['connected'] as bool,
            wired: item['if_type'] == 6));
      }
      final wired = adapters.where((a) => a.wired);
      final partial =
          raw['query_errors'] is int ? raw['query_errors'] as int : 0;
      final state = wired.any((a) => a.connected)
          ? AdapterScanState.detected
          : partial > 0
              ? AdapterScanState.failed
              : wired.isNotEmpty
                  ? AdapterScanState.disconnected
                  : AdapterScanState.absent;
      final diagnostic = <String>[
        'source=ip_helper',
        'elapsed_ms=${clock.elapsedMilliseconds}',
        'state=${state.name}',
        'query_errors=$partial',
        for (final a in adapters)
          'wired=${a.wired}, connected=${a.connected}, mac=**:**:**:${a.mac.substring(9)}',
      ].join('\n');
      return WindowsAdapterScan(state, List.unmodifiable(adapters), diagnostic);
    } on PlatformException catch (e) {
      final details = e.details;
      const apiNames = {'GetAdaptersAddresses', 'GetIfEntry2'};
      final api = details is Map && apiNames.contains(details['api'])
          ? details['api']
          : 'native';
      final code = details is Map && details['code'] is int
          ? details['code']
          : 'unknown';
      return _failed('api=$api\ncode=$code', clock);
    } on MissingPluginException {
      return _failed('code=native_unavailable', clock);
    } on TimeoutException {
      return _failed('code=timeout', clock);
    } on FormatException {
      return _failed('code=invalid_response', clock);
    }
  }

  WindowsAdapterScan _failed(String reason, Stopwatch clock) =>
      WindowsAdapterScan(AdapterScanState.failed, const [],
          'source=ip_helper\nelapsed_ms=${clock.elapsedMilliseconds}\n$reason');

  Future<List<WindowsWakeAdapter>> adapters() async {
    final result = await scan();
    if (result.state == AdapterScanState.failed) {
      throw WakeApiException('adapter_query', result.message);
    }
    return result.adapters;
  }
}
