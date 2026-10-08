import '../models/wake.dart';

/// Presentation group within one account and server. Members remain intact.
class WakeTargetGroup {
  final WakeTarget primary;
  final List<WakeTarget> members;

  const WakeTargetGroup({required this.primary, required this.members});
}

String wakeTargetGroupKey(WakeTarget target) {
  final mac = target.mac.trim().replaceAll('-', ':').toUpperCase();
  if (!RegExp(r'^(?:[0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(mac)) {
    return 'target:${target.id}';
  }
  final bytes = mac.split(':').map((part) => int.parse(part, radix: 16));
  if (bytes.every((byte) => byte == 0) || (bytes.first & 1) != 0) {
    return 'target:${target.id}';
  }
  return 'mac:$mac';
}

/// Callers must supply targets from a single account/server scope.
List<WakeTargetGroup> groupWakeTargets(Iterable<WakeTarget> targets,
    {Set<String> accountDeviceIds = const {}}) {
  final groups = <String, List<WakeTarget>>{};
  for (final target in targets) {
    groups.putIfAbsent(wakeTargetGroupKey(target), () => []).add(target);
  }
  int preferTrue(bool a, bool b) => a == b ? 0 : (a ? -1 : 1);
  return groups.values.map((members) {
    members.sort((a, b) {
      final online = preferTrue(
          accountDeviceIds.contains(a.deviceId) || a.online,
          accountDeviceIds.contains(b.deviceId) || b.online);
      if (online != 0) return online;
      final recent = (b.lastSeenMs ?? 0).compareTo(a.lastSeenMs ?? 0);
      if (recent != 0) return recent;
      final helper = preferTrue(a.agentOnline, b.agentOnline);
      if (helper != 0) return helper;
      final configured = preferTrue(a.setupComplete, b.setupComplete);
      return configured != 0 ? configured : a.id.compareTo(b.id);
    });
    return WakeTargetGroup(
        primary: members.first, members: List.unmodifiable(members));
  }).toList();
}
