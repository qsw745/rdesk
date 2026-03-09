enum SessionState {
  idle,
  connecting,
  authenticating,
  active,
  disconnected,
  error,
}

class SessionInfo {
  final String sessionId;
  final String peerId;
  final String peerHostname;
  final String peerOs;
  final SessionState state;
  final DateTime connectedAt;
  final int? latencyMs;

  const SessionInfo({
    required this.sessionId,
    required this.peerId,
    required this.peerHostname,
    required this.peerOs,
    required this.state,
    required this.connectedAt,
    this.latencyMs,
  });

  SessionInfo copyWith({
    SessionState? state,
    int? latencyMs,
  }) {
    return SessionInfo(
      sessionId: sessionId,
      peerId: peerId,
      peerHostname: peerHostname,
      peerOs: peerOs,
      state: state ?? this.state,
      connectedAt: connectedAt,
      latencyMs: latencyMs ?? this.latencyMs,
    );
  }
}
