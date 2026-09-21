import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/wake.dart';
import '../models/wake_diagnostic.dart';
import '../providers/wake_provider.dart';

class WakeTestScreen extends StatefulWidget {
  final String targetId;
  const WakeTestScreen({super.key, required this.targetId});
  @override
  State<WakeTestScreen> createState() => _WakeTestScreenState();
}

class _WakeTestScreenState extends State<WakeTestScreen>
    with WidgetsBindingObserver {
  WakeProvider? _wake;
  int? _generation;
  String _environment = '未选择', _observation = '尚未观察', _requestId = '';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _wake = context.read<WakeProvider>();
        _generation = _wake!.identityGeneration;
        _wake!.setVisible(true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _wake?.setVisible(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    _wake?.setVisible(false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wake = context.watch<WakeProvider>();
    final target =
        wake.targets.where((t) => t.id == widget.targetId).firstOrNull;
    final current = wake.loggedIn &&
        (_generation == null || _generation == wake.identityGeneration);
    final requests = wake.history[widget.targetId] ?? <WakeRequest>[];
    final latest = requests.firstOrNull;
    if (_requestId != (latest?.id ?? '')) {
      _requestId = latest?.id ?? '';
      _observation = '尚未观察';
    }
    final helper =
        wake.agents.where((a) => a.id == target?.agentId).firstOrNull;
    return Scaffold(
        appBar: AppBar(title: const Text('开机测试与诊断'), actions: [
          IconButton(
              onPressed: wake.refresh,
              icon: const Icon(Icons.refresh),
              tooltip: '刷新')
        ]),
        body: !current
            ? const Center(child: Text('账号或服务器已变更，请返回。'))
            : target == null
                ? const Center(child: Text('未找到开机配置，请返回刷新。'))
                : Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: ListView(
                            padding: const EdgeInsets.all(20),
                            children: [
                              Text(target.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall),
                              const SizedBox(height: 12),
                              Text(
                                  '家中助手：${helper?.name ?? '未选择'} · ${target.agentOnline ? '在线' : '离线'}'),
                              const SizedBox(height: 16),
                              const Text(
                                  '先保存电脑上的工作，自行睡眠或关机。外网测试时，让本手机关闭 Wi-Fi 使用蜂窝网络，家中助手保持在线。'),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                  value: _environment,
                                  decoration: const InputDecoration(
                                      labelText: '这次从哪里测试（手动选择）'),
                                  items: [
                                    for (final s in [
                                      '未选择',
                                      '家中局域网',
                                      '外网／蜂窝网络',
                                      '隔夜外网测试',
                                      '24 小时后外网测试',
                                      '48 小时后外网测试'
                                    ])
                                      DropdownMenuItem(value: s, child: Text(s))
                                  ],
                                  onChanged: wake.busy
                                      ? null
                                      : (s) =>
                                          setState(() => _environment = s!)),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                  icon: const Icon(Icons.power_settings_new),
                                  label: Text(latest?.active == true
                                      ? '正在测试…'
                                      : '发送测试开机指令'),
                                  onPressed: wake.busy ||
                                          !target.setupComplete ||
                                          target.online ||
                                          !target.agentOnline ||
                                          requests.any((r) => r.active)
                                      ? null
                                      : () async {
                                          await wake.wake(target);
                                        }),
                              if (target.online)
                                const Text('电脑应用仍在线。自行睡眠或关机后等待离线，再发送测试。'),
                              if (!target.setupComplete)
                                const Text('请先完成 BIOS 确认和助手绑定。'),
                              if (wake.error != null)
                                Text(wake.error!,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error)),
                              const SizedBox(height: 20),
                              Text(wakeNextStep(latest, target.agentOnline),
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              if (latest != null) ...[
                                const SizedBox(height: 12),
                                SelectableText('请求编号：${latest.id}'),
                                for (final item in <(String, int?)>[
                                  ('服务器接受', latest.createdAtMs),
                                  ('助手领取', latest.claimedAtMs),
                                  ('发包回执', latest.sentAtMs),
                                  ('电脑应用上线', latest.onlineAtMs)
                                ])
                                  ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(item.$2 == null
                                          ? Icons.radio_button_unchecked
                                          : Icons.check_circle_outline),
                                      title: Text(item.$1),
                                      subtitle:
                                          Text(wakeDiagnosticTime(item.$2))),
                                if (latest.errorCode != null)
                                  SelectableText('诊断代码：${latest.errorCode}'),
                                DropdownButtonFormField<String>(
                                    value: _observation,
                                    decoration: const InputDecoration(
                                        labelText: '实际观察结果（复制报告时包含）'),
                                    items: [
                                      for (final s in [
                                        '尚未观察',
                                        '电脑确实启动了',
                                        '仍然没有开机',
                                        '已启动，停在登录界面',
                                        '本次由我手动开机'
                                      ])
                                        DropdownMenuItem(
                                            value: s, child: Text(s))
                                    ],
                                    onChanged: (s) =>
                                        setState(() => _observation = s!)),
                              ],
                              const SizedBox(height: 20),
                              OutlinedButton.icon(
                                  icon: const Icon(Icons.copy),
                                  label: const Text('复制诊断报告'),
                                  onPressed: () async {
                                    await Clipboard.setData(ClipboardData(
                                        text: wakeDiagnosticReport(
                                            target: target,
                                            helper: helper,
                                            requests: requests,
                                            environment: _environment,
                                            observation: _observation)));
                                    if (context.mounted)
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text(
                                                  '诊断已复制，不含账号凭据、MAC 或 IP')));
                                  }),
                              const Text(
                                  '云端开机记录保留最近 7 天、最多 50 条。人工观察只加入本次复制的报告，请复制保存。退出页面不会自动关机或重发指令。'),
                            ]))));
  }
}
