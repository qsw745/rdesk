import '../models/account.dart';
import '../models/address_book.dart';
import '../models/connection_info.dart';
import '../models/device_directory_entry.dart';
import '../models/wake.dart';
import 'wake_target_group.dart';

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
  // Only shipped HTTP aliases of the official service share this identity.
  // Unknown sources and arbitrary self-hosted HTTP origins stay separate.
  if (uri.scheme == 'http' &&
      uri.host.toLowerCase() == 'qisw.top' &&
      (uri.port == 80 || uri.port == 21116)) {
    return 'https://qisw.top';
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
  final groups = scope == null
      ? wakeTargets
          .map((t) => WakeTargetGroup(primary: t, members: [t]))
          .toList()
      : groupWakeTargets(wakeTargets,
          accountDeviceIds: accountDevices.map((d) => d.deviceId).toSet());
  final aliases = <String, String>{};
  final groupByDeviceId = <String, WakeTargetGroup>{};
  if (scope != null) {
    for (final group in groups) {
      groupByDeviceId[group.primary.deviceId] = group;
      for (final member in group.members) {
        aliases[member.deviceId] = group.primary.deviceId;
      }
    }
  }
  void put(String id, String? source,
      {String? name,
      String? platform,
      bool? online,
      bool? favorite,
      bool? accountOwned,
      bool? canHost,
      bool? hosting,
      DateTime? lastSeen,
      WakeTarget? wake}) {
    final sourceScope = normalizedEndpointScope(source);
    final currentScope = scope != null && sourceScope == scope;
    final deviceId = currentScope ? aliases[id] ?? id : id;
    final key = deviceDirectoryKey(sourceScope, deviceId);
    final old = rows[key];
    final group = currentScope ? groupByDeviceId[deviceId] : null;
    final otherIds = group?.members
            .map((t) => t.deviceId)
            .where((id) => id != deviceId)
            .toSet()
            .toList() ??
        <String>[];
    otherIds.sort();
    final relatedIds =
        group == null ? const <String>[] : [deviceId, ...otherIds];
    rows[key] = DeviceDirectoryEntry(
        key: key,
        deviceId: deviceId,
        name: name?.isNotEmpty == true ? name! : old?.name ?? deviceId,
        platform:
            platform?.isNotEmpty == true ? platform! : old?.platform ?? '未知系统',
        endpointScope: sourceScope,
        online: online ?? old?.online ?? false,
        favorite: favorite ?? old?.favorite ?? false,
        accountOwned: accountOwned ?? old?.accountOwned ?? false,
        lastSeen: lastSeen != null &&
                (old?.lastSeen == null || lastSeen.isAfter(old!.lastSeen!))
            ? lastSeen
            : old?.lastSeen,
        wakeTarget: wake ?? old?.wakeTarget,
        canHost: canHost ?? old?.canHost,
        hosting: hosting ?? old?.hosting,
        relatedDeviceIds: List.unmodifiable(relatedIds),
        aliasKeys: List.unmodifiable(relatedIds
            .map((id) => deviceDirectoryKey(sourceScope, id))
            .where((alias) => alias != key)));
  }

  final sortedHistory = List<ConnectionRecord>.of(history)
    ..sort((a, b) => a.connectedAt.compareTo(b.connectedAt));
  for (final h in sortedHistory) {
    put(h.peerId, h.endpointScope,
        name: h.peerHostname, platform: h.peerOs, lastSeen: h.connectedAt);
  }
  for (final group in groups) {
    final t = group.primary;
    put(t.deviceId, scope,
        name: t.name,
        platform: 'windows',
        online: group.members.any((t) => t.online),
        wake: t);
  }
  for (final d in accountDevices) {
    put(d.deviceId, scope,
        name: d.hostname,
        platform: d.platform,
        online: true,
        accountOwned: true,
        canHost: d.canHost,
        hosting: d.hosting,
        lastSeen: d.updatedAt);
  }
  for (final s in saved) {
    put(s.deviceId, s.endpointScope,
        name: s.alias,
        favorite: true,
        platform: rows.containsKey(deviceDirectoryKey(
                s.endpointScope,
                normalizedEndpointScope(s.endpointScope) == scope &&
                        scope != null
                    ? aliases[s.deviceId] ?? s.deviceId
                    : s.deviceId))
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
