enum SessionState {
  idle,
  connecting,
  authenticating,
  reconnecting,
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

  /// Measured network round-trip to the remote host, in milliseconds.
  final int? latencyMs;

  /// Age of the displayed frame (now − host capture time), in milliseconds.
  ///
  /// This is a picture-freshness diagnostic, not a latency measure: it keeps
  /// growing while the remote screen is static and no new frames are produced.
  final int? frameAgeMs;

  const SessionInfo({
    required this.sessionId,
    required this.peerId,
    required this.peerHostname,
    required this.peerOs,
    required this.state,
    required this.connectedAt,
    this.latencyMs,
    this.frameAgeMs,
  });

  SessionInfo copyWith({
    SessionState? state,
    int? latencyMs,
    bool clearLatency = false,
    int? frameAgeMs,
    bool clearFrameAge = false,
  }) {
    return SessionInfo(
      sessionId: sessionId,
      peerId: peerId,
      peerHostname: peerHostname,
      peerOs: peerOs,
      state: state ?? this.state,
      connectedAt: connectedAt,
      latencyMs: clearLatency ? null : latencyMs ?? this.latencyMs,
      frameAgeMs: clearFrameAge ? null : frameAgeMs ?? this.frameAgeMs,
    );
  }
}
