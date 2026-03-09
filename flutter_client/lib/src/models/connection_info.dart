class ConnectionRecord {
  final String peerId;
  final String peerHostname;
  final String peerOs;
  final DateTime connectedAt;
  final DateTime? disconnectedAt;
  final String connectionType; // "p2p" or "relay"

  const ConnectionRecord({
    required this.peerId,
    required this.peerHostname,
    required this.peerOs,
    required this.connectedAt,
    this.disconnectedAt,
    required this.connectionType,
  });

  Duration? get duration => disconnectedAt?.difference(connectedAt);
}
