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

  const AccountDevice({
    required this.deviceId,
    required this.hostname,
    required this.platform,
    required this.updatedAtMs,
  });

  DateTime get updatedAt =>
      DateTime.fromMillisecondsSinceEpoch(updatedAtMs, isUtc: true).toLocal();
}
