import 'wake.dart';

String wakeDiagnosticTime(int? ms) => ms == null
    ? '未收到'
    : DateTime.fromMillisecondsSinceEpoch(ms).toLocal().toIso8601String();
String wakeNextStep(WakeRequest? request, bool helperOnline) {
  if (request == null)
    return helperOnline ? '保存工作后自行让电脑睡眠或关机，再发送测试请求。' : '先让家中的助手在线，当前无法发送。';
  return switch (request.phase) {
    WakePhase.queued => '服务器已收到请求，等待家中助手领取。',
    WakePhase.claimed => '助手已领取，请等待发送回执。',
    WakePhase.sent => '助手已发包；请观察电脑电源，等待 RDesk 应用上线。',
    WakePhase.online => '已收到应用心跳，请核对是否本次唤醒。人工开机也会产生心跳。',
    WakePhase.unconfirmed => '未收到应用心跳。先检查电脑是否停在登录界面；若确实没启动，再检查供电、BIOS 和网卡。',
    WakePhase.expired => '请求过期。检查家中助手的联网状态，再发起新测试。',
    _ => '查看诊断代码，检查助手日志与网络后重新测试。',
  };
}

String wakeDiagnosticReport(
        {required WakeTarget target,
        required WakeAgent? helper,
        required List<WakeRequest> requests,
        required String environment,
        required String observation}) =>
    [
      'RDesk 远程开机测试',
      '生成时间：${DateTime.now().toLocal().toIso8601String()}',
      '测试网络（用户选择，未自动验证）：$environment',
      '当前助手：${helper == null ? '未选择' : '已绑定助手'}；${helper?.online == true ? '在线' : '离线'}',
      '人工观察（仅对应最近一次请求）：$observation',
      '发包回执和应用心跳均不能单独证明硬件被本次请求唤醒。',
      for (final r in requests.take(10)) ...[
        '',
        '请求：${r.id}',
        '状态：${wakePhaseLabel(r.phase)}',
        '服务器接受：${wakeDiagnosticTime(r.createdAtMs)}',
        '助手领取：${wakeDiagnosticTime(r.claimedAtMs)}',
        '发送回执：${wakeDiagnosticTime(r.sentAtMs)}',
        '应用上线：${wakeDiagnosticTime(r.onlineAtMs)}',
        if (r.errorCode != null) '诊断代码：${r.errorCode}',
      ],
      '',
      '建议：${wakeNextStep(requests.firstOrNull, target.agentOnline)}',
    ].join('\n');
