import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/wake.dart';
import '../providers/connection_provider.dart';
import '../providers/wake_provider.dart';
import '../services/desktop_wake_agent.dart';
import '../services/login_item_service.dart';
import '../services/wake_agent_channel.dart';
import '../services/windows_wake_service.dart';
import '../ui/components.dart';
import '../ui/device_actions.dart';
import '../ui/tokens.dart';
import '../utils/platform_capabilities.dart';

/// Remote wake in one place: this PC's switch (Windows), this device as a
/// home helper (Android, macOS) and the PCs the account can wake.
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
      if (!mounted) return;
      _wake = context.read<WakeProvider>()..setVisible(true);
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
    final platform = defaultTargetPlatform;
    final isWindows = platform == TargetPlatform.windows;
    final canHelp =
        platform == TargetPlatform.android || platform == TargetPlatform.macOS;

    if (!wake.loggedIn) {
      return RdPage(
          title: '远程开机',
          leading: PlatformCapabilities.current.isDesktop
              ? null
              : IconButton(
                  onPressed: () => context.go('/me'),
                  tooltip: '返回',
                  icon: const Icon(Icons.arrow_back_rounded)),
          children: [
            const SizedBox(height: 40),
            RdEmptyState(
              icon: Icons.power_settings_new_rounded,
              title: '登录后使用远程开机',
              message: '电脑和手机登录同一账号，就能在外面一键开机家里的电脑。',
              action: FilledButton(
                  onPressed: () => context.push('/login'),
                  child: const Text('登录')),
            ),
          ]);
    }

    final back = PlatformCapabilities.current.isDesktop
        ? null
        : IconButton(
            onPressed: () => context.go('/me'),
            tooltip: '返回',
            icon: const Icon(Icons.arrow_back_rounded));
    return RdPage(
      title: '远程开机',
      subtitle: '电脑关机或睡眠时，用手机一键开机',
      leading: back,
      onRefresh: wake.refresh,
      actions: [
        IconButton(
            onPressed: wake.refresh,
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded)),
      ],
      children: [
        if (wake.error != null) ...[
          RdCard(
            color: RdPalette.of(context).dangerSoft,
            child: Text(wake.error!,
                style: TextStyle(color: RdPalette.of(context).danger)),
          ),
          const SizedBox(height: 16),
        ],
        if (isWindows) ...[
          const RdSectionHeader('这台电脑'),
          const _LocalPcCard(),
          const SizedBox(height: 24),
        ],
        if (canHelp) ...[
          const RdSectionHeader('开机助手'),
          const _HelperCard(),
          const SizedBox(height: 24),
        ],
        const RdSectionHeader('可开机的电脑'),
        const _TargetList(),
        const SizedBox(height: 24),
        const _HowItWorks(),
      ],
    );
  }
}

// ── This Windows PC ─────────────────────────────────────────────────────────

class _LocalPcCard extends StatefulWidget {
  const _LocalPcCard();
  @override
  State<_LocalPcCard> createState() => _LocalPcCardState();
}

class _LocalPcCardState extends State<_LocalPcCard> {
  WindowsAdapterScan? _scan;
  WindowsWakeCheck? _check;
  bool? _startup;
  bool _scanning = false;

  WindowsWakeService? get _service => context.read<WakeProvider>().windows;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _inspect());
  }

  WindowsWakeAdapter? get _adapter {
    final wired =
        _scan?.adapters.where((a) => a.wired && a.connected).toList() ?? [];
    return wired.length == 1 ? wired.single : wired.firstOrNull;
  }

  Future<void> _inspect() async {
    final service = _service;
    if (service == null || !mounted) return;
    setState(() => _scanning = true);
    try {
      final scan = await service.scanAdapters();
      if (!mounted) return;
      setState(() => _scan = scan);
      final adapter = _adapter;
      final results = await Future.wait<Object?>([
        service
            .loginStartupEnabled()
            .then<Object?>((v) => v, onError: (Object _) => null),
        if (adapter != null)
          service
              .inspect(adapter.mac)
              .then<Object?>((v) => v, onError: (Object _) => null),
      ]);
      if (!mounted) return;
      setState(() {
        _startup = results.first as bool?;
        _check = results.length > 1 ? results[1] as WindowsWakeCheck? : null;
      });
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _enable() async {
    final wake = context.read<WakeProvider>();
    final local = context.read<ConnectionProvider>().localDevice;
    final messenger = ScaffoldMessenger.of(context);
    final adapter = _adapter;
    if (local == null) {
      messenger.showSnackBar(const SnackBar(content: Text('正在获取本机设备码，请稍后再试')));
      return;
    }
    if (adapter == null) {
      messenger.showSnackBar(
          const SnackBar(content: Text('没有找到连接中的有线网卡。远程开机需要电脑用网线连接路由器。')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('开启远程开机'),
        content: const SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _Requirement(
                icon: Icons.settings_ethernet_rounded,
                text: '电脑用网线连接路由器，关机后保持通电'),
            _Requirement(
                icon: Icons.memory_rounded,
                text: '主板 BIOS 已开启「网络唤醒 / Wake on LAN」'),
            _Requirement(
                icon: Icons.phonelink_ring_rounded,
                text: '家里有一台常开的安卓手机或 Mac 作为开机助手'),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('开启')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final service = _service;
    if (service != null && _startup != true) {
      try {
        await service.setLoginStartup(true);
        if (mounted) setState(() => _startup = true);
      } catch (e) {
        debugPrint('[RDesk] login startup not changed: $e');
      }
    }
    await wake.enableLocalWake(
        deviceId: local.deviceId,
        name:
            local.hostname.isNotEmpty ? local.hostname : Platform.localHostname,
        mac: adapter.mac);
  }

  Future<void> _disable(String deviceId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('关闭远程开机？'),
        content: const Text('关闭后将无法从手机开机这台电脑，可以随时重新开启。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('关闭')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<WakeProvider>().disableLocalWake(deviceId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wake = context.watch<WakeProvider>();
    final p = RdPalette.of(context);
    final t = Theme.of(context).textTheme;
    final local = context.watch<ConnectionProvider>().localDevice;
    final target = local == null ? null : wake.targetForDevice(local.deviceId);
    final enabled = target != null || wake.localWakePending;
    final helper = target == null
        ? null
        : wake.agents.where((a) => a.id == target.agentId).firstOrNull;
    final adapter = _adapter;

    final String status;
    final RdTone tone;
    if (wake.localWakePending) {
      status = '等待家中开机助手：在家里的安卓手机或 Mac 上打开随控，开启「开机助手」后自动完成';
      tone = RdTone.warning;
    } else if (target != null) {
      final helperOnline = target.agentOnline;
      status = helper == null
          ? '已开启'
          : helperOnline
              ? '已开启 · 家中助手：${helper.name}（在线）'
              : '已开启，但家中助手「${helper.name}」离线，现在无法开机。请在那台设备上打开随控 →「远程开机」→ 开启开机助手，并让它保持开机不睡眠';
      tone = helperOnline ? RdTone.online : RdTone.warning;
    } else {
      status = '开启后，可以在手机上一键开机这台电脑';
      tone = RdTone.neutral;
    }

    String checkLabel(WakeCheckState s) => switch (s) {
          WakeCheckState.enabled => '已开启',
          WakeCheckState.disabled => '未开启',
          WakeCheckState.unknown => '无法判断',
        };
    RdTone checkTone(WakeCheckState s) => switch (s) {
          WakeCheckState.enabled => RdTone.online,
          WakeCheckState.disabled => RdTone.danger,
          WakeCheckState.unknown => RdTone.neutral,
        };
    Widget checkRow(String label, WakeCheckState s) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Expanded(child: Text(label, style: t.bodyMedium)),
            RdStatusPill(checkLabel(s), tone: checkTone(s)),
          ]),
        );

    final check = _check;
    return RdCard(
      padding: const EdgeInsets.all(18),
      radius: Rd.radiusLg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const RdIconBadge(
              icon: Icons.power_settings_new_rounded,
              tone: RdTone.power,
              size: 40),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('允许远程开机', style: t.titleMedium),
              const SizedBox(height: 2),
              Text(status,
                  style: t.bodySmall!.copyWith(
                      color: tone == RdTone.neutral
                          ? p.inkSecondary
                          : tone.fg(p))),
            ]),
          ),
          const SizedBox(width: 8),
          Switch(
            value: enabled,
            onChanged: wake.busy || _scanning || local == null
                ? null
                : (v) => v ? _enable() : _disable(local.deviceId),
          ),
        ]),
        const SizedBox(height: 16),
        Divider(color: p.divider),
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.settings_ethernet_rounded, size: 18, color: p.inkTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                _scanning
                    ? '正在检测网卡…'
                    : adapter != null
                        ? '有线网卡：${adapter.name}'
                        : _scan?.message ?? '尚未检测网卡',
                style: t.bodyMedium),
          ),
          TextButton(
              onPressed: _scanning ? null : _inspect,
              child: const Text('重新检测')),
        ]),
        if (check != null) ...[
          checkRow('魔术包唤醒', check.magicPacket),
          checkRow('允许网卡唤醒电脑', check.wakeArmed),
          checkRow('关机后网络唤醒', check.shutdownWake),
          if (!check.allEnabled)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _service?.openDeviceManager(),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('打开设备管理器，在网卡「高级」和「电源管理」中开启'),
              ),
            ),
        ],
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('登录 Windows 后自动启动随控'),
          subtitle: const Text('电脑开机后自动上线，才能确认开机成功并连接'),
          value: _startup ?? false,
          onChanged: _startup == null
              ? null
              : (v) async {
                  try {
                    await _service?.setLoginStartup(v);
                    if (mounted) setState(() => _startup = v);
                  } catch (_) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('无法修改开机启动，请在 Windows「启动应用」中设置')));
                  }
                },
        ),
        const _BiosTips(),
      ]),
    );
  }
}

class _Requirement extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Requirement({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          RdIconBadge(icon: icon, size: 32),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ]),
      );
}

class _BiosTips extends StatelessWidget {
  const _BiosTips();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text('如何在 BIOS 中开启网络唤醒', style: t.bodyMedium),
        children: [
          for (final line in const [
            '1. 重启电脑，开机时按 Del、F2 或 F12 进入 BIOS（不同品牌按键不同）。',
            '2. 在「电源管理 / Power」或「高级 / Advanced」中找到「Wake on LAN」「PCIE 唤醒」等选项，设为 Enabled。',
            '3. 如有「ErP / EuP」节能选项，请关闭，否则关机后网卡会断电。',
            '4. 按 F10 保存并重启。建议在 Windows 电源选项中关闭「快速启动」。',
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(line, style: t.bodySmall),
            ),
        ],
      ),
    );
  }
}

// ── This device as a home helper ───────────────────────────────────────────

class _HelperCard extends StatefulWidget {
  const _HelperCard();
  @override
  State<_HelperCard> createState() => _HelperCardState();
}

class _HelperCardState extends State<_HelperCard> {
  bool _working = false;
  LoginItemState _login = const LoginItemState();
  final _loginItem = const LoginItemService();
  bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    if (_isMac) {
      _loginItem.status().then((v) {
        if (mounted) setState(() => _login = v);
      }, onError: (Object e) => debugPrint('[RDesk] login item: $e'));
    }
  }

  Future<void> _enable() async {
    final wake = context.read<WakeProvider>();
    final gen = wake.identityGeneration;
    setState(() => _working = true);
    try {
      if (_isMac) {
        final networks = await wake.agent.desktop.networks();
        if (!mounted || gen != wake.identityGeneration) return;
        var network = pickHomeNetwork(networks);
        if (network == null && networks.isNotEmpty) {
          network = await showDialog<DesktopWakeNetwork>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: const Text('选择电脑所在的家庭网络'),
              children: [
                for (final n in networks)
                  SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, n),
                      child: Text('${n.name} · ${n.cidr}')),
              ],
            ),
          );
        }
        if (network == null) {
          if (mounted && networks.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('没有找到家庭局域网，请连接电脑所在的 Wi-Fi 或网线')));
          }
          return;
        }
        wake.agent.desktop.selected = network;
      }
      await wake.enableHelper(_isMac ? '家中 Mac' : '家中安卓手机');
    } on StateError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wake = context.watch<WakeProvider>();
    final p = RdPalette.of(context);
    final t = Theme.of(context).textTheme;
    final on = wake.helper.enabled;
    final code = wake.helper.errorCode;
    final status = code != null
        ? describeHelperError(code)
        : on
            ? '运行中 · 家里的电脑可以通过这台${_isMac ? ' Mac' : '手机'}开机'
            : '让这台${_isMac ? ' Mac' : '手机'}帮家里的电脑开机，需要一直留在家中联网';
    return RdCard(
      padding: const EdgeInsets.all(18),
      radius: Rd.radiusLg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          RdIconBadge(
              icon: _isMac
                  ? Icons.laptop_mac_rounded
                  : Icons.phonelink_ring_rounded,
              tone: on ? RdTone.online : RdTone.brand,
              size: 40),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('作为家中开机助手', style: t.titleMedium),
              const SizedBox(height: 2),
              Text(status,
                  style: t.bodySmall!.copyWith(
                      color: code != null
                          ? p.warning
                          : on
                              ? p.online
                              : p.inkSecondary)),
            ]),
          ),
          const SizedBox(width: 8),
          Switch(
            value: on,
            onChanged: _working || wake.busy
                ? null
                : (v) => v ? _enable() : wake.disableHelper(),
          ),
        ]),
        if (_isMac && _login.supported) ...[
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('登录 Mac 后自动打开随控'),
            subtitle: Text(_login.requiresApproval
                ? '需要在系统设置的「登录项」中允许随控'
                : 'Mac 重启或更新后，助手会在同一家庭网络自动恢复'),
            value: _login.enabled || _login.requiresApproval,
            onChanged: (v) async {
              try {
                final next = await _loginItem.set(v);
                if (mounted) setState(() => _login = next);
              } on PlatformException catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.message ?? '无法更改登录项')));
              }
            },
          ),
        ],
        if (!_isMac) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Text('建议保持充电，并允许随控后台运行，避免被系统休眠。', style: t.bodySmall),
            ),
            TextButton(
                onPressed: wake.agent.openBatterySettings,
                child: const Text('后台设置')),
          ]),
        ],
      ]),
    );
  }
}

// ── PCs this account can wake ───────────────────────────────────────────────

class _TargetList extends StatelessWidget {
  const _TargetList();

  @override
  Widget build(BuildContext context) {
    final wake = context.watch<WakeProvider>();
    final t = Theme.of(context).textTheme;
    if (wake.targets.isEmpty) {
      return RdCard(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          const RdIconBadge(icon: Icons.desktop_windows_rounded, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('还没有可开机的电脑', style: t.titleSmall),
              const SizedBox(height: 4),
              Text('在需要开机的 Windows 电脑上安装随控，登录同一账号，打开「远程开机」开启即可。',
                  style: t.bodySmall),
            ]),
          ),
        ]),
      );
    }
    return Column(children: [
      for (final target in wake.targets)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _TargetCard(target: target),
        ),
      if (wake.usableHelpers.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: Row(children: [
            Icon(Icons.home_rounded,
                size: 16, color: RdPalette.of(context).inkTertiary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                  '家中助手：${wake.usableHelpers.map((a) => '${a.name}（${a.online ? '在线' : '离线'}）').join('、')}',
                  style: t.bodySmall),
            ),
          ]),
        ),
    ]);
  }
}

class _TargetCard extends StatelessWidget {
  final WakeTarget target;
  const _TargetCard({required this.target});

  Future<void> _changeHelper(BuildContext context) async {
    final wake = context.read<WakeProvider>();
    final picked = await showDialog<WakeAgent>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择家中助手'),
        children: [
          for (final a in wake.usableHelpers)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, a),
              child: Row(children: [
                RdStatusDot(
                    color: a.online
                        ? RdPalette.of(ctx).online
                        : RdPalette.of(ctx).inkTertiary),
                const SizedBox(width: 10),
                Expanded(child: Text(a.name)),
                if (a.id == target.agentId) const Text('当前'),
              ]),
            ),
        ],
      ),
    );
    if (picked != null && picked.id != target.agentId) {
      await wake.rebind(target, picked.id);
    }
  }

  Future<void> _remove(BuildContext context) async {
    final wake = context.read<WakeProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('移除「${target.name}」？'),
        content: const Text('移除后将无法远程开机这台电脑，需要在电脑上重新开启。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('移除')),
        ],
      ),
    );
    if (ok == true) await wake.remove(target);
  }

  @override
  Widget build(BuildContext context) {
    final wake = context.watch<WakeProvider>();
    final p = RdPalette.of(context);
    final t = Theme.of(context).textTheme;
    final latest = wake.history[target.id]?.firstOrNull;
    final waking = latest?.active ?? false;
    final (String label, RdTone tone) = target.online
        ? ('在线', RdTone.online)
        : waking
            ? ('正在开机', RdTone.power)
            : latest?.phase == WakePhase.unconfirmed
                ? ('已发送，未等到上线', RdTone.warning)
                : ('离线', RdTone.neutral);
    return RdCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(children: [
        RdDeviceGlyph(platform: 'windows', online: target.online),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(target.name, style: t.titleMedium),
            const SizedBox(height: 4),
            Row(children: [
              RdStatusPill(label, tone: tone),
              if (!target.online && !target.agentOnline) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text('助手离线',
                      style: t.labelSmall!.copyWith(color: p.warning)),
                ),
              ],
            ]),
          ]),
        ),
        if (!target.online)
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: p.power,
                minimumSize: const Size(80, 38),
                padding: const EdgeInsets.symmetric(horizontal: 14)),
            onPressed:
                waking || wake.busy ? null : () => wakeDevice(context, target),
            icon: const Icon(Icons.power_settings_new_rounded, size: 18),
            label: Text(waking ? '开机中' : '开机'),
          ),
        PopupMenuButton<String>(
          tooltip: '更多',
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (v) => switch (v) {
            'helper' => _changeHelper(context),
            'remove' => _remove(context),
            _ => null,
          },
          itemBuilder: (_) => [
            if (wake.usableHelpers.length > 1)
              const PopupMenuItem(value: 'helper', child: Text('更换家中助手')),
            const PopupMenuItem(value: 'remove', child: Text('移除这台电脑')),
          ],
        ),
      ]),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = RdPalette.of(context);
    Widget step(IconData icon, String title, String body) => Expanded(
          child: Column(children: [
            RdIconBadge(icon: icon, size: 40),
            const SizedBox(height: 8),
            Text(title, style: t.titleSmall, textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text(body, style: t.bodySmall, textAlign: TextAlign.center),
          ]),
        );
    Widget arrow() => Padding(
          padding: const EdgeInsets.only(top: 12),
          child:
              Icon(Icons.arrow_forward_rounded, size: 18, color: p.inkTertiary),
        );
    return RdCard(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 18),
      color: p.surfaceMuted,
      child: Column(children: [
        Text('工作原理', style: t.labelMedium),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          step(Icons.smartphone_rounded, '你点开机', '在外面用手机'),
          arrow(),
          step(Icons.phonelink_ring_rounded, '家中助手', '收到后在局域网发出唤醒'),
          arrow(),
          step(Icons.desktop_windows_rounded, '电脑启动', '上线后即可远程连接'),
        ]),
      ]),
    );
  }
}
