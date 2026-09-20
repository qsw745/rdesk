import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/wake.dart';
import '../providers/wake_provider.dart';
import '../services/rdesk_bridge_service.dart';
import '../services/windows_wake_service.dart';

class WakeScreen extends StatefulWidget {
  const WakeScreen({super.key});
  @override
  State<WakeScreen> createState() => _WakeScreenState();
}

class _WakeScreenState extends State<WakeScreen> with WidgetsBindingObserver {
  WakeProvider? _wake;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _wake = context.read<WakeProvider>();
        _wake!.setVisible(true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _wake?.setVisible(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    _wake?.setVisible(false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wake = context.watch<WakeProvider>();
    return Scaffold(
        appBar: AppBar(title: const Text('远程开机'), actions: [
          IconButton(
              onPressed: wake.refresh,
              icon: const Icon(Icons.refresh),
              tooltip: '刷新'),
        ]),
        body: !wake.loggedIn
            ? Center(
                child: FilledButton(
                    onPressed: () => context.push('/login?redirect=/wake'),
                    child: const Text('登录后配置远程开机')))
            : RefreshIndicator(
                onRefresh: wake.refresh,
                child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      const Text('人在外面，也能发起开机',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('家中安卓手机负责发送唤醒信号。电脑需要接网线、保持电源接通，并支持网络唤醒。'),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                          onPressed: () async {
                            wake.setVisible(false);
                            await context.push('/wake/setup');
                            if (mounted) wake.setVisible(true);
                          },
                          icon: const Icon(Icons.settings_outlined),
                          label: const Text('配置电脑与开机助手')),
                      if (wake.error != null) _notice(wake.error!, error: true),
                      if (wake.targets.isEmpty && wake.error == null)
                        _notice('尚未添加电脑。先在家中的安卓手机启用助手，再到 Windows 电脑完成配置。'),
                      for (final target in wake.targets)
                        _target(context, wake, target),
                    ])));
  }

  Widget _target(BuildContext context, WakeProvider wake, WakeTarget target) {
    final requests = wake.history[target.id] ?? [];
    final pending = requests.any((r) => r.active);
    final helper = wake.agents.where((a) => a.id == target.agentId).firstOrNull;
    return Card(
        margin: const EdgeInsets.only(top: 16),
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(target.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(target.online ? '电脑应用在线' : '电脑应用离线'),
              Text(target.agentOnline ? '家中助手在线' : '家中助手离线，请先检查手机网络和后台运行'),
              Text('助手最近在线：${_time(helper?.lastSeenMs)}'),
              if (requests.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(wakePhaseLabel(requests.first.phase))),
              if (requests.isNotEmpty &&
                  requests.first.phase == WakePhase.unconfirmed)
                const Text('信号已发出，但尚未收到电脑应用的上线心跳。请检查主板、网卡唤醒设置，以及 RDesk 是否启动。'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                FilledButton.icon(
                    onPressed: wake.busy ||
                            target.online ||
                            !target.agentOnline ||
                            pending
                        ? null
                        : () => wake.wake(target),
                    icon: const Icon(Icons.power_settings_new),
                    label: Text(pending ? '正在开机…' : '开机')),
                TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => SafeArea(
                            child: SizedBox(
                                height: 420,
                                child: ListView(
                                    padding: const EdgeInsets.all(20),
                                    children: [
                                      const Text('开机记录',
                                          style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold)),
                                      const Text('保留最近 7 天、最多 50 条记录。'),
                                      if (requests.isEmpty)
                                        const ListTile(title: Text('暂无开机记录')),
                                      for (final request in requests)
                                        ListTile(
                                            title: Text(
                                                wakePhaseLabel(request.phase)),
                                            subtitle: Text(
                                                '提交：${_time(request.createdAtMs)}\n领取：${_time(request.claimedAtMs)}\n发送回执：${_time(request.sentAtMs)}\n电脑上线：${_time(request.onlineAtMs)}${request.errorCode == null ? '' : '\n诊断代码：${request.errorCode}'}')),
                                    ])))),
                    child: const Text('查看记录')),
                TextButton(
                    onPressed: wake.busy
                        ? null
                        : () async {
                            final selected = await showDialog<String>(
                                context: context,
                                builder: (ctx) => SimpleDialog(
                                        title: const Text('更换家中助手'),
                                        children: [
                                          for (final helper in wake.agents
                                              .where((a) => a.enabled))
                                            SimpleDialogOption(
                                                onPressed: () => Navigator.pop(
                                                    ctx, helper.id),
                                                child: Text(helper.name)),
                                          if (!wake.agents
                                              .any((a) => a.enabled))
                                            const Padding(
                                                padding: EdgeInsets.all(20),
                                                child: Text('请先在家中安卓手机启用助手')),
                                        ]));
                            if (selected != null) {
                              await wake.rebind(target, selected);
                            }
                          },
                    child: const Text('更换助手')),
                TextButton(
                    onPressed: wake.busy
                        ? null
                        : () async {
                            final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                        title: const Text('移除开机配置？'),
                                        content: Text(
                                            '将移除“${target.name}”的开机配置，并取消未完成的请求。'),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: const Text('取消')),
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: const Text('移除'))
                                        ]));
                            if (confirmed == true) await wake.remove(target);
                          },
                    child: const Text('移除')),
              ]),
            ])));
  }
}

String _time(int? ms) => ms == null
    ? '未收到'
    : DateTime.fromMillisecondsSinceEpoch(ms)
        .toLocal()
        .toString()
        .split('.')
        .first;

Widget _notice(String text, {bool error = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child:
        Text(text, style: TextStyle(color: error ? Colors.deepOrange : null)));

class WakeSetupScreen extends StatefulWidget {
  const WakeSetupScreen({super.key});
  @override
  State<WakeSetupScreen> createState() => _WakeSetupScreenState();
}

class _WakeSetupScreenState extends State<WakeSetupScreen>
    with WidgetsBindingObserver {
  WakeProvider? _wake;
  final _name = TextEditingController();
  List<WindowsWakeAdapter>? _adapters;
  String? _mac, _agentId, _error;
  bool _ready = false, _loading = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _name.text = Platform.isAndroid ? '家中安卓手机' : '我的 Windows 电脑';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _wake = context.read<WakeProvider>();
        _wake!.setVisible(true);
        unawaited(_load());
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final wake = context.read<WakeProvider>();
    try {
      await wake.refresh();
      final adapters = await wake.windows?.adapters();
      if (mounted) {
        setState(() {
          _adapters = adapters;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '无法读取网卡，请确认在 Windows 电脑上操作';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _wake?.setVisible(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    _wake?.setVisible(false);
    WidgetsBinding.instance.removeObserver(this);
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wake = context.watch<WakeProvider>();
    return Scaffold(
        appBar: AppBar(title: const Text('配置远程开机')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('1. 家中的安卓手机',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text(
              '登录同一账号，连接与电脑相同的家庭 Wi-Fi（不要使用访客网络），长期供电。开启助手后，允许后台运行和自启动，并将电池策略设为不限制。锁屏后仍需实际测试。'),
          if (Platform.isAndroid && wake.loggedIn) ...[
            TextField(
                controller: _name,
                maxLength: 40,
                decoration: const InputDecoration(labelText: '助手名称')),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('本机开机助手'),
                subtitle: Text(wake.helper.enabled ? '已启动，可在通知栏停止' : '已停止'),
                value: wake.helper.enabled,
                onChanged: wake.busy
                    ? null
                    : (enabled) async {
                        if (enabled) {
                          await wake.enableHelper(_name.text.trim());
                        } else {
                          await wake.disableHelper();
                        }
                        if (mounted) setState(() {});
                      }),
            Text(wake.helper.networkReady ? '家庭 Wi-Fi 通道可用' : '家庭 Wi-Fi 通道未就绪'),
            if (wake.helper.errorCode != null)
              Text('助手停止或重试原因：${wake.helper.errorCode}'),
            TextButton(
                onPressed: wake.agent.openBatterySettings,
                child: const Text('打开电池优化设置')),
            const Text(
                '切换 Wi-Fi 后助手会停止，请回到家中 Wi-Fi 后重新启用。手机重启或被强制结束后，也需要打开应用重新启用。'),
          ],
          const SizedBox(height: 24),
          if (wake.agents.isNotEmpty)
            ExpansionTile(title: const Text('管理已登记的助手'), children: [
              for (final helper in wake.agents)
                ListTile(
                    title: Text(helper.name),
                    subtitle: Text(
                        '${helper.online ? '在线' : helper.enabled ? '离线' : '已停用'} · 最近在线：${_time(helper.lastSeenMs)}'),
                    trailing: IconButton(
                        tooltip: '删除助手',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: wake.busy
                            ? null
                            : () async {
                                final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                            title: const Text('删除助手？'),
                                            content: const Text(
                                                '绑定此助手的电脑需要在远程开机页更换助手，才能再次开机。'),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, false),
                                                  child: const Text('取消')),
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, true),
                                                  child: const Text('删除'))
                                            ]));
                                if (confirmed == true) {
                                  await wake.removeHelper(helper);
                                }
                              })),
            ]),
          const Text('2. Windows 电脑',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text(
              '将电脑网线接到小米 AX3000 的局域网端口。在主板 BIOS 中开启 Wake on LAN / PCIe 唤醒，关闭会切断网卡待机供电的 ErP。网卡高级属性中开启 Magic Packet 唤醒。具体选项以主板和网卡说明为准。'),
          _notice(
              '先测试睡眠唤醒，再测试关机唤醒。Windows 快速启动、休眠和关机的支持情况因硬件与驱动而异。请为 RDesk 配置开机登录后自动启动，否则可能显示“未确认上线”。'),
          if (Platform.isWindows && wake.loggedIn) ...[
            TextField(
                controller: _name,
                maxLength: 40,
                decoration: const InputDecoration(labelText: '电脑名称')),
            if (_loading) const LinearProgressIndicator(),
            DropdownButtonFormField<String>(
                initialValue: _mac,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '实际连接路由器的有线网卡'),
                items: [
                  for (final adapter in _adapters ?? <WindowsWakeAdapter>[])
                    DropdownMenuItem(
                        value: adapter.mac,
                        enabled: adapter.wired && adapter.connected,
                        child: Text(
                            '${adapter.name} · ${adapter.mac}${adapter.wired && adapter.connected ? '' : '（不可选）'}'))
                ],
                onChanged: (value) => setState(() {
                      _mac = value;
                    })),
            DropdownButtonFormField<String>(
                initialValue: _agentId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '家中开机助手'),
                items: [
                  for (final helper in wake.agents.where((a) => a.enabled))
                    DropdownMenuItem(
                        value: helper.id,
                        child: Text(
                            '${helper.name} · ${helper.online ? '在线' : '离线'}'))
                ],
                onChanged: (value) => setState(() {
                      _agentId = value;
                    })),
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('已确认主板和网卡支持网络唤醒，电脑保持接通电源'),
                value: _ready,
                onChanged: (value) => setState(() {
                      _ready = value ?? false;
                    })),
            FilledButton(
                onPressed: wake.busy ||
                        !_ready ||
                        _mac == null ||
                        _agentId == null ||
                        _name.text.trim().isEmpty
                    ? null
                    : () async {
                        final local = await RdeskBridgeService.instance
                            .getLocalDeviceInfo();
                        if (!mounted) return;
                        final ok = await wake.enrollWindows(
                            deviceId: local.deviceId,
                            name: _name.text.trim(),
                            mac: _mac!,
                            agentId: _agentId!);
                        if (ok && context.mounted) context.pop();
                      },
                child: const Text('保存这台电脑')),
            TextButton(
                onPressed: _loading ? null : _load,
                child: const Text('刷新网卡与助手')),
          ] else
            _notice('请在要开机的 Windows 电脑上，登录同一账号并进入此页选择有线网卡和家中助手。'),
          const SizedBox(height: 24),
          const Text('3. 外网与隔夜测试',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text(
              '在手机关闭 Wi-Fi、使用移动网络发起开机，分别测试刚关机、隔夜、24 小时与 48 小时。失败时先查看助手是否在线，再查看发送记录，最后核对电脑电源与网卡设置。无需在路由器开放公网唤醒端口。'),
          _notice('远程开机仅负责唤醒电脑。当前 Windows 客户端不提供被控桌面功能。'),
          if (!wake.loggedIn)
            FilledButton(
                onPressed: () => context.push('/login?redirect=/wake/setup'),
                child: const Text('登录账号')),
          if (wake.windows?.lastError != null)
            _notice(wake.windows!.lastError!, error: true),
          if (wake.error != null || _error != null)
            _notice(_error ?? wake.error!, error: true),
        ]));
  }
}
