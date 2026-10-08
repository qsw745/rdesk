import 'wake.dart';

class DeviceDirectoryEntry {
  final String key, deviceId, name, platform;
  final String? endpointScope;
  final bool online, favorite;

  /// True only for the current server account device snapshot.
  final bool accountOwned;
  final DateTime? lastSeen;
  final WakeTarget? wakeTarget;

  /// Confirmed device-code aliases in this entry's server scope.
  final List<String> relatedDeviceIds;

  /// Directory routes for older confirmed device-code aliases.
  final List<String> aliasKeys;
  const DeviceDirectoryEntry(
      {required this.key,
      required this.deviceId,
      required this.name,
      required this.platform,
      required this.endpointScope,
      required this.online,
      required this.favorite,
      this.accountOwned = false,
      this.lastSeen,
      this.wakeTarget,
      this.relatedDeviceIds = const [],
      this.aliasKeys = const []});
}
