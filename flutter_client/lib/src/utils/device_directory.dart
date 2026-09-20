import '../models/account.dart';
import '../models/address_book.dart';
import '../models/connection_info.dart';
import '../models/device_directory_entry.dart';
import '../models/wake.dart';

String? normalizedEndpointScope(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final raw = value.trim();
  final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
  if (uri == null ||
      !{'https', 'http'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri.origin.toLowerCase();
}

String deviceDirectoryKey(String? scope, String id) =>
    '${normalizedEndpointScope(scope) ?? 'legacy'}|$id';

List<DeviceDirectoryEntry> mergeDeviceDirectory(
    {required String endpointScope,
    required List<AccountDevice> accountDevices,
    required List<ConnectionRecord> history,
    required List<AddressBookEntry> saved,
    required List<WakeTarget> wakeTargets}) {
  final scope = normalizedEndpointScope(endpointScope);
  final rows = <String, DeviceDirectoryEntry>{};
  void put(String id, String? source,
      {String? name,
      String? platform,
      bool? online,
      bool? favorite,
      DateTime? lastSeen,
      WakeTarget? wake}) {
    final key = deviceDirectoryKey(source, id);
    final old = rows[key];
    rows[key] = DeviceDirectoryEntry(
        key: key,
        deviceId: id,
        name: name?.isNotEmpty == true ? name! : old?.name ?? id,
        platform:
            platform?.isNotEmpty == true ? platform! : old?.platform ?? '未知系统',
        endpointScope: normalizedEndpointScope(source),
        online: online ?? old?.online ?? false,
        favorite: favorite ?? old?.favorite ?? false,
        lastSeen: lastSeen ?? old?.lastSeen,
        wakeTarget: wake ?? old?.wakeTarget);
  }

  final sortedHistory = List<ConnectionRecord>.of(history)
    ..sort((a, b) => a.connectedAt.compareTo(b.connectedAt));
  for (final h in sortedHistory) {
    put(h.peerId, h.endpointScope,
        name: h.peerHostname, platform: h.peerOs, lastSeen: h.connectedAt);
  }
  for (final t in wakeTargets) {
    put(t.deviceId, scope,
        name: t.name, platform: 'windows', online: t.online, wake: t);
  }
  for (final d in accountDevices) {
    put(d.deviceId, scope,
        name: d.hostname,
        platform: d.platform,
        online: true,
        lastSeen: d.updatedAt);
  }
  for (final s in saved) {
    put(s.deviceId, s.endpointScope,
        name: s.alias,
        favorite: true,
        platform:
            rows.containsKey(deviceDirectoryKey(s.endpointScope, s.deviceId))
                ? null
                : s.platform);
  }
  return rows.values.toList()
    ..sort((a, b) {
      if (a.online != b.online) return a.online ? -1 : 1;
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      final recent = (b.lastSeen?.millisecondsSinceEpoch ?? 0)
          .compareTo(a.lastSeen?.millisecondsSinceEpoch ?? 0);
      return recent != 0 ? recent : a.key.compareTo(b.key);
    });
}
