enum WakePhase {
  queued,
  claimed,
  sent,
  online,
  unconfirmed,
  expired,
  failed,
  cancelled,
  interrupted,
  unknown
}

class WakeTarget {
  final String id, name, deviceId, mac, agentId;
  final bool online, agentOnline;
  final int revision;
  final int? lastSeenMs;
  const WakeTarget(
      {required this.id,
      required this.name,
      required this.deviceId,
      required this.mac,
      required this.agentId,
      required this.online,
      required this.agentOnline,
      required this.revision,
      this.lastSeenMs});
  factory WakeTarget.fromJson(Map<String, dynamic> j) => WakeTarget(
      id: _id(j),
      name: j['name'] as String,
      deviceId: j['device_id'] as String,
      mac: j['mac'] as String,
      agentId: j['agent_id'] as String,
      online: j['online'] == true,
      agentOnline: j['agent_online'] == true,
      revision: (j['revision'] as num).toInt(),
      lastSeenMs: (j['last_seen_ms'] as num?)?.toInt());
}

class WakeAgent {
  final String id, name;
  final bool online, enabled;
  final int? lastSeenMs;
  const WakeAgent(
      {required this.id,
      required this.name,
      required this.online,
      required this.enabled,
      this.lastSeenMs});
  factory WakeAgent.fromJson(Map<String, dynamic> j) => WakeAgent(
      id: _id(j),
      name: j['name'] as String,
      online: j['online'] == true,
      enabled: j['enabled'] == true,
      lastSeenMs: (j['last_seen_ms'] as num?)?.toInt());
}

class WakeEnrollment {
  final String id, token;
  const WakeEnrollment(this.id, this.token);
  factory WakeEnrollment.fromJson(Map<String, dynamic> j) =>
      WakeEnrollment(_id(j), j['token'] as String);
}

class WakeRequest {
  final String id, targetId;
  final WakePhase phase;
  final int createdAtMs;
  final int? claimedAtMs, sentAtMs, onlineAtMs;
  final String? errorCode;
  const WakeRequest(
      {required this.id,
      required this.targetId,
      required this.phase,
      required this.createdAtMs,
      this.claimedAtMs,
      this.sentAtMs,
      this.onlineAtMs,
      this.errorCode});
  bool get active =>
      phase == WakePhase.queued ||
      phase == WakePhase.claimed ||
      phase == WakePhase.sent;
  factory WakeRequest.fromJson(Map<String, dynamic> j) => WakeRequest(
      id: _id(j),
      targetId: j['target_id'] as String,
      phase: WakePhase.values.where((p) => p.name == j['phase']).firstOrNull ??
          WakePhase.unknown,
      createdAtMs: (j['created_at_ms'] as num).toInt(),
      claimedAtMs: (j['claimed_at_ms'] as num?)?.toInt(),
      sentAtMs: (j['sent_at_ms'] as num?)?.toInt(),
      onlineAtMs: (j['online_at_ms'] as num?)?.toInt(),
      errorCode: j['error_code'] as String?);
}

String _id(Map<String, dynamic> j) {
  final id = j['id'];
  if (id is! String || id.isEmpty) throw const FormatException('开机数据缺少标识');
  return id;
}

String wakePhaseLabel(WakePhase p) => switch (p) {
      WakePhase.queued => '请求已提交',
      WakePhase.claimed => '助手正在发送',
      WakePhase.sent => '信号已发送，等待电脑上线',
      WakePhase.online => '电脑已上线',
      WakePhase.unconfirmed => '未确认上线',
      WakePhase.expired => '请求已过期',
      WakePhase.failed => '发送失败',
      WakePhase.cancelled => '请求已取消',
      WakePhase.interrupted => '服务中断，请重新尝试',
      WakePhase.unknown => '状态暂不可用',
    };
