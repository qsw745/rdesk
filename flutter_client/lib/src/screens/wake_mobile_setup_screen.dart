import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/wake.dart';
import '../providers/wake_provider.dart';
import '../utils/platform_capabilities.dart';

class WakeMobileSetupScreen extends StatefulWidget {
  final String targetId;
  const WakeMobileSetupScreen({super.key, required this.targetId});
  @override
  State<WakeMobileSetupScreen> createState() => _WakeMobileSetupScreenState();
}

class _WakeMobileSetupScreenState extends State<WakeMobileSetupScreen>
    with WidgetsBindingObserver {
  WakeProvider? _wake;
  int _step = 0;
  String? _agent;
  bool _bios = false, _initialized = false;
  int? _accountGeneration;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _wake = context.read<WakeProvider>();
        _accountGeneration = _wake!.identityGeneration;
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
    if (!_initialized && target != null) {
      _initialized = true;
      _step = target.setupComplete ? 2 : 0;
      _agent = target.agentId.isEmpty ? null : target.agentId;
    }
    final helpers = wake.agents.where((a) => a.enabled).toList();
    if (_agent == null) {
      final online = helpers.where((a) => a.online).toList();
      if (online.length == 1) _agent = online.first.id;
    }
    final valid = helpers.any((a) => a.id == _agent);
    final current = wake.loggedIn &&
        (_accountGeneration == null ||
            _accountGeneration == wake.identityGeneration);
    return Scaffold(
        appBar: AppBar(title: const Text('配置远程开机')),
        body: !current
            ? const Center(child: Text('账号或服务器已变更，请返回设备列表。'))
            : target == null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(wake.error ?? '正在读取电脑配置…'),
                    TextButton(
                        onPressed: wake.refresh, child: const Text('重新加载'))
                  ]))
                : Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: ListView(
                            padding: const EdgeInsets.all(20),
                            children: [
                              Text(target.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall),
                              const SizedBox(height: 16),
                              Wrap(spacing: 12, runSpacing: 8, children: [
                                for (var i = 0; i < 3; i++)
                                  Chip(
                                      avatar:
                                          CircleAvatar(child: Text('${i + 1}')),
                                      label: Text(['家中助手', 'BIOS 设置', '测试'][i]),
                                      backgroundColor: _step == i
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primaryContainer
                                          : null)
                              ]),
                              const SizedBox(height: 24),
                              Card(
                                  child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            if (_step == 0) ...[
                                              Text('选择留在家里的助手',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleLarge),
                                              const SizedBox(height: 12),
                                              const Text(
                                                  '安卓手机需连接与电脑相同的家庭 Wi-Fi，并长期供电。外出时仍由它代发开机信号。'),
                                              const SizedBox(height: 16),
                                              if (helpers.isEmpty)
                                                const Text(
                                                    '尚无家中助手\n在留家的安卓手机安装 RDesk，登录同一账号，打开“远程开机 → 作为家中开机助手”。'),
                                              for (final helper in helpers)
                                                RadioListTile<String>(
                                                    value: helper.id,
                                                    groupValue: _agent,
                                                    onChanged: wake.busy
                                                        ? null
                                                        : (id) => setState(
                                                            () => _agent = id),
                                                    title: Text(helper.name),
                                                    subtitle: Text(helper.online
                                                        ? '在线'
                                                        : '离线 · 请检查家中手机')),
                                              if (_agent != null && !valid)
                                                const Text(
                                                    '原助手已停用或被移除，请明确选择新的助手。'),
                                              if (PlatformCapabilities
                                                      .current.canRelayWake &&
                                                  !wake.helper.enabled)
                                                TextButton(
                                                    onPressed: wake.busy
                                                        ? null
                                                        : () =>
                                                            wake.enableHelper(
                                                                '家中安卓手机'),
                                                    child: const Text(
                                                        '将这台安卓手机设为家中助手')),
                                              const SizedBox(height: 16),
                                              FilledButton(
                                                  onPressed: !valid || wake.busy
                                                      ? null
                                                      : () => setState(
                                                          () => _step = 1),
                                                  child: const Text('下一步')),
                                              TextButton(
                                                  onPressed: wake.refresh,
                                                  child: const Text('刷新助手')),
                                            ] else if (_step == 1) ...[
                                              Text('核对电脑 BIOS',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleLarge),
                                              const SizedBox(height: 16),
                                              const Text(
                                                  '1. 开机时按 F2 或 Del 进入 BIOS。\n\n2. 将 Wake on LAN 或 Wake on PCI-E 设为 Enabled。\n\n3. 将 ErP 节能设为 Disabled，让关机后的网卡继续供电。\n\n4. 保存设置。电脑保持插电和网线连接。'),
                                              const SizedBox(height: 16),
                                              const Text(
                                                  '不同主板选项不同，可查阅电脑或主板说明书。RDesk 无法自动验证 BIOS。'),
                                              CheckboxListTile(
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  value: _bios,
                                                  onChanged: (v) => setState(
                                                      () => _bios = v ?? false),
                                                  title: const Text(
                                                      '已核对 BIOS 和供电设置')),
                                              FilledButton(
                                                  onPressed: !_bios ||
                                                          !valid ||
                                                          wake.busy
                                                      ? null
                                                      : () async {
                                                          final gen = wake
                                                              .identityGeneration;
                                                          final ok = await wake
                                                              .completeTarget(
                                                                  target.id,
                                                                  _agent!);
                                                          if (mounted &&
                                                              ok &&
                                                              gen ==
                                                                  wake.identityGeneration) {
                                                            setState(() =>
                                                                _step = 2);
                                                          }
                                                        },
                                                  child: Text(wake.busy
                                                      ? '正在保存…'
                                                      : '保存，进入测试')),
                                              TextButton(
                                                  onPressed: wake.busy
                                                      ? null
                                                      : () => setState(
                                                          () => _step = 0),
                                                  child: const Text('上一步')),
                                            ] else ...[
                                              Text('测试远程开机',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleLarge),
                                              const SizedBox(height: 12),
                                              const Text(
                                                  '请先自行保存电脑上的工作，让电脑进入睡眠，再点下方按钮。测试关机唤醒和外出开机时，手机切换为蜂窝网络。'),
                                              const SizedBox(height: 16),
                                              if (target.online)
                                                const Text(
                                                    '电脑应用当前在线。请在电脑上自行进入睡眠后再测试。'),
                                              if (!target.agentOnline)
                                                const Text(
                                                    '家中助手离线，请检查网络与后台运行权限。'),
                                              const SizedBox(height: 16),
                                              for (final r
                                                  in (wake.history[target.id] ??
                                                          [])
                                                      .take(1))
                                                Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            bottom: 12),
                                                    child: Text(wakePhaseLabel(
                                                        r.phase))),
                                              FilledButton.icon(
                                                  onPressed: wake.busy ||
                                                          target.online ||
                                                          !target.agentOnline ||
                                                          !target
                                                              .setupComplete ||
                                                          (wake.history[
                                                                      target.id]
                                                                  ?.any((r) => r
                                                                      .active) ??
                                                              false)
                                                      ? null
                                                      : () => wake.wake(target),
                                                  icon: const Icon(
                                                      Icons.power_settings_new),
                                                  label: const Text('发送开机信号')),
                                              const SizedBox(height: 12),
                                              const Text(
                                                  '信号发送成功不代表电脑已开机。收到电脑 RDesk 的上线心跳后，才会显示“电脑已上线”。'),
                                              TextButton(
                                                  onPressed: () =>
                                                      setState(() => _step = 0),
                                                  child: const Text('修改配置')),
                                            ],
                                            if (wake.error != null)
                                              Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 12),
                                                  child: Text(wake.error!,
                                                      style: TextStyle(
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .error))),
                                          ]))),
                            ]))));
  }
}
