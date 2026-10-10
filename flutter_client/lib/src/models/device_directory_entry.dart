import 'wake.dart';

class DeviceDirectoryEntry {
  final String key, deviceId, name, platform;
  final String? endpointScope;
  final bool online, favorite;

  /// True only for the current server account device snapshot.
  final bool accountOwned;
  final DateTime? lastSeen;
  final WakeTarget? wakeTarget;

  /// Whether the device's client can be remotely controlled, as reported in
  /// the account snapshot. Null for entries the account has not reported.
  final bool? canHost;

  /// Whether the device currently accepts connections; null when unknown.
  final bool? hosting;

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
      this.canHost,
      this.hosting,
      this.relatedDeviceIds = const [],
      this.aliasKeys = const []});
}
