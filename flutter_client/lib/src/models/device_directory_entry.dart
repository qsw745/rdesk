import 'wake.dart';

class DeviceDirectoryEntry {
  final String key, deviceId, name, platform;
  final String? endpointScope;
  final bool online, favorite;
  final DateTime? lastSeen;
  final WakeTarget? wakeTarget;
  const DeviceDirectoryEntry(
      {required this.key,
      required this.deviceId,
      required this.name,
      required this.platform,
      required this.endpointScope,
      required this.online,
      required this.favorite,
      this.lastSeen,
      this.wakeTarget});
}
