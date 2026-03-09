class TrustedPeer {
  final String deviceId;
  final String hostname;
  final String peerOs;
  final DateTime savedAt;
  final DateTime lastUsedAt;

  const TrustedPeer({
    required this.deviceId,
    required this.hostname,
    required this.peerOs,
    required this.savedAt,
    required this.lastUsedAt,
  });
}
