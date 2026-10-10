class AccountSession {
  final String token;
  final String userId;
  final String username;
  final String displayName;

  const AccountSession({
    required this.token,
    required this.userId,
    required this.username,
    required this.displayName,
  });
}

class AccountDevice {
  final String deviceId;
  final String hostname;
  final String platform;
  final int updatedAtMs;

  /// Reported by the device's own client; older builds never report it.
  final bool canHost;

  /// Whether the server holds a fresh host registration for the device.
  /// Null when the server predates the field.
  final bool? hosting;

  const AccountDevice({
    required this.deviceId,
    required this.hostname,
    required this.platform,
    required this.updatedAtMs,
    this.canHost = false,
    this.hosting,
  });

  DateTime get updatedAt =>
      DateTime.fromMillisecondsSinceEpoch(updatedAtMs, isUtc: true).toLocal();
}
