import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/device_directory_entry.dart';
import '../models/wake.dart';
import '../providers/wake_provider.dart';
import '../ui/components.dart';
import '../ui/device_actions.dart';
import '../ui/tokens.dart';

/// One device, UU-style: a large "enter desktop" card and quick actions.
class DeviceDetailScreen extends StatelessWidget {
  final String deviceKey;
  const DeviceDetailScreen({super.key, required this.deviceKey});

  @override
  Widget build(BuildContext context) {
    final entry = watchDeviceDirectory(context)
        .where((e) => e.key == deviceKey || e.aliasKeys.contains(deviceKey))
        .firstOrNull;
    if (entry == null) {
      return Scaffold(
        appBar: AppBar(),
        body: RdEmptyState(
          icon: Icons.devices_other_rounded,
          title: '找不到这台设备',
          message: '它可能已从账号或收藏中移除。',
          action: FilledButton(
              onPressed: () => context.go('/'), child: const Text('返回设备列表')),
        ),
      );
    }
    return _DeviceView(entry: entry);
  }
}

class _DeviceView extends StatelessWidget {
  final DeviceDirectoryEntry entry;
  const _DeviceView({required this.entry});

  @override
  Widget build(BuildContext context) {
    final wake = context.watch<WakeProvider>();
    final abilities = DeviceAbilities.of(context, entry);
    final status = deviceStatus(entry, wake);
    final target = entry.wakeTarget;
    final wide = RdPage.wide(context);
    final t = Theme.of(context).textTheme;
    final connectable = canConnectNow(entry, abilities);

    final actions = <Widget>[
      if (abilities.canControl) ...[
        RdActionButton(
            icon: Icons.desktop_windows_rounded,
            label: '远程控制',
            onTap: connectable ? () => connectToDevice(context, entry) : null),
        RdActionButton(
            icon: Icons.folder_copy_rounded,
            label: '文件传输',
            onTap: connectable
                ? () => connectToDevice(context, entry, files: true)
                : null),
      ],
      if (abilities.canWake && target != null)
        RdActionButton(
            icon: Icons.power_settings_new_rounded,
            label: '远程开机',
            tone: RdTone.power,
            onTap: entry.online || wake.busy || wake.isWaking(target)
                ? null
                : () => wakeDevice(context, target)),
      RdActionButton(
          icon: entry.favorite ? Icons.star_rounded : Icons.star_border_rounded,
          label: entry.favorite ? '已收藏' : '收藏',
          tone: RdTone.warning,
          onTap: () => toggleFavorite(context, entry)),
      RdActionButton(
          icon: Icons.content_copy_rounded,
          label: '复制设备码',
          tone: RdTone.neutral,
          onTap: () {
            Clipboard.setData(ClipboardData(text: entry.deviceId));
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('设备码已复制')));
          }),
    ];

    final hero = _HeroCard(entry: entry, abilities: abilities, status: status);
    final actionRow = RdCard(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Row(children: [
        for (final a in actions) Expanded(child: a),
      ]),
    );
    final info = _InfoCard(entry: entry);
    final wakeCard =
        target == null ? null : _WakeCard(target: target, online: entry.online);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: wide ? 32 : 4,
        title: Row(children: [
          Flexible(
              child: Text(entry.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 10),
          RdStatusPill(status.label, tone: status.tone),
        ]),
        actions: [
          _MoreMenu(entry: entry),
          SizedBox(width: wide ? 24 : 8),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(wide ? 32 : 16, 8, wide ? 32 : 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Expanded(
                              flex: 3,
                              child: Column(children: [
                                hero,
                                const SizedBox(height: 16),
                                actionRow,
                              ])),
                          const SizedBox(width: 20),
                          Expanded(
                              flex: 2,
                              child: Column(children: [
                                if (wakeCard != null) ...[
                                  wakeCard,
                                  const SizedBox(height: 16),
                                ],
                                info,
                              ])),
                        ])
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                          hero,
                          const SizedBox(height: 18),
                          actionRow,
                          const SizedBox(height: 20),
                          if (wakeCard != null) ...[
                            const RdSectionHeader('远程开机'),
                            wakeCard,
                            const SizedBox(height: 20),
                          ],
                          const RdSectionHeader('设备信息'),
                          info,
                        ]),
            ),
          ),
          if (abilities.unsupportedReason != null && !abilities.isLocal)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(abilities.unsupportedReason!,
                  textAlign: TextAlign.center, style: t.bodySmall),
            ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final DeviceDirectoryEntry entry;
  final DeviceAbilities abilities;
  final ({String label, RdTone tone}) status;
  const _HeroCard(
      {required this.entry, required this.abilities, required this.status});

  @override
  Widget build(BuildContext context) {
    final p = RdPalette.of(context);
    final t = Theme.of(context).textTheme;
    final wake = context.watch<WakeProvider>();
    final target = entry.wakeTarget;
    final waking = status.tone == RdTone.power;
    final live = canConnectNow(entry, abilities);
    final platform = rdPlatformOf(entry.platform);

    final Widget cta;
    final String caption;
    if (live) {
      caption = entry.online ? '点击进入远程桌面' : '对方打开随控后即可连接';
      cta = ValueListenableBuilder<String?>(
        valueListenable: connectingDevice,
        builder: (context, key, _) => FilledButton.icon(
          style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: p.brandInk,
              minimumSize: const Size(0, 46),
              padding: const EdgeInsets.symmetric(horizontal: 22)),
          onPressed: key != null ? null : () => connectToDevice(context, entry),
          icon: key == entry.key
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.arrow_forward_rounded, size: 20),
          label: Text(key == entry.key ? '正在连接' : '进入桌面'),
        ),
      );
    } else if (!entry.online && abilities.canWake && target != null) {
      caption = waking ? '已发出开机信号，等待电脑启动…' : '电脑已关机或休眠';
      cta = FilledButton.icon(
        style: FilledButton.styleFrom(
            backgroundColor: p.power,
            minimumSize: const Size(0, 46),
            padding: const EdgeInsets.symmetric(horizontal: 22)),
        onPressed:
            waking || wake.busy ? null : () => wakeDevice(context, target),
        icon: waking
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.power_settings_new_rounded, size: 20),
        label: Text(waking ? '正在开机' : '远程开机'),
      );
    } else {
      caption = abilities.unsupportedReason ??
          (entry.online ? '设备在线' : '设备离线，上线后即可连接');
      cta = const SizedBox.shrink();
    }

    final gradient = live
        ? const LinearGradient(
            colors: [Color(0xFF3A7BFF), Color(0xFF1D3FC0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight)
        : LinearGradient(colors: [
            p.surfaceMuted,
            Color.lerp(p.surfaceMuted, p.border, 0.6)!,
          ], begin: Alignment.topLeft, end: Alignment.bottomRight);
    final fg = live ? Colors.white : p.ink;
    final sub = live ? Colors.white.withValues(alpha: 0.78) : p.inkSecondary;

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(Rd.radiusXl),
          border: live ? null : Border.all(color: p.border),
          boxShadow: live
              ? [
                  BoxShadow(
                      color: const Color(0xFF1D3FC0).withValues(alpha: 0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 6))
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          // Stylised desktop: a window frame hinting at the remote screen.
          Positioned(
            right: -30,
            top: 24,
            child: Opacity(
              opacity: live ? 0.16 : 0.5,
              child: Icon(platform.icon,
                  size: 200, color: live ? Colors.white : p.border),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(platform.icon, size: 18, color: sub),
                const SizedBox(width: 6),
                Text(platform.label,
                    style: t.labelMedium!.copyWith(color: sub)),
              ]),
              const Spacer(),
              Text(entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.headlineSmall!.copyWith(color: fg)),
              const SizedBox(height: 4),
              Text(caption, style: t.bodySmall!.copyWith(color: sub)),
              const SizedBox(height: 16),
              cta,
            ]),
          ),
        ]),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final DeviceDirectoryEntry entry;
  const _InfoCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = RdPalette.of(context);
    String source() {
      if (entry.endpointScope == null) return '来源未记录，连接前会确认服务器';
      if (entry.accountOwned) return '同一账号';
      if (entry.favorite) return '已收藏';
      if (entry.wakeTarget != null) return '远程开机';
      return '连接记录';
    }

    String? last() {
      final v = entry.lastSeen;
      if (v == null) return null;
      final l = v.toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${l.month}月${l.day}日 ${two(l.hour)}:${two(l.minute)}';
    }

    Widget row(String k, String v, {bool mono = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(children: [
            SizedBox(
                width: 84,
                child: Text(k,
                    style: t.bodySmall!.copyWith(color: p.inkTertiary))),
            Expanded(
                child: SelectableText(v,
                    style: t.bodyMedium!.copyWith(
                        fontWeight: mono ? FontWeight.w600 : null,
                        letterSpacing: mono ? 0.5 : null))),
          ]),
        );
    final lastSeen = last();
    return RdCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(children: [
        row('设备码', formatDeviceId(entry.deviceId), mono: true),
        row('系统', rdPlatformOf(entry.platform).label),
        row('来源', source()),
        if (lastSeen != null) row(entry.online ? '最近更新' : '最近在线', lastSeen),
      ]),
    );
  }
}

class _WakeCard extends StatelessWidget {
  final WakeTarget target;
  final bool online;
  const _WakeCard({required this.target, required this.online});

  @override
  Widget build(BuildContext context) {
    final wake = context.watch<WakeProvider>();
    final t = Theme.of(context).textTheme;
    final p = RdPalette.of(context);
    final helper = wake.agents.where((a) => a.id == target.agentId).firstOrNull;
    final latest = wake.latestRequestForTarget(target);
    final (String, RdTone)? result = online
        ? ('电脑已上线', RdTone.online)
        : latest == null
            ? null
            : switch (latest.phase) {
                WakePhase.queued || WakePhase.claimed => (
                    '正在发送开机信号',
                    RdTone.power
                  ),
                WakePhase.sent => ('已发出，等待电脑上线', RdTone.power),
                WakePhase.online => ('上次开机成功', RdTone.online),
                WakePhase.unconfirmed => ('已发出，但未等到电脑上线', RdTone.warning),
                WakePhase.expired ||
                WakePhase.failed ||
                WakePhase.interrupted =>
                  ('上次开机没有成功', RdTone.danger),
                WakePhase.cancelled => ('上次开机已取消', RdTone.neutral),
                WakePhase.unknown => null,
              };
    return RdCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const RdIconBadge(
              icon: Icons.power_settings_new_rounded, tone: RdTone.power),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(target.setupComplete ? '已开启远程开机' : '远程开机未完成设置',
                    style: t.titleSmall),
                const SizedBox(height: 2),
                Text(
                    helper == null
                        ? '家中助手已被移除'
                        : '家中助手：${helper.name} · ${target.agentOnline ? '在线' : '离线'}',
                    style: t.bodySmall!.copyWith(
                        color:
                            target.agentOnline ? p.inkSecondary : p.warning)),
              ])),
        ]),
        if (result != null) ...[
          const SizedBox(height: 12),
          RdStatusPill(result.$1, tone: result.$2),
        ],
        if (!target.agentOnline && !online) ...[
          const SizedBox(height: 12),
          Text('家中没有在线的开机助手。请确认家里的安卓手机或 Mac 已打开随控并开启"开机助手"。',
              style: t.bodySmall),
        ],
      ]),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  final DeviceDirectoryEntry entry;
  const _MoreMenu({required this.entry});

  @override
  Widget build(BuildContext context) {
    final target = entry.wakeTarget;
    return PopupMenuButton<String>(
      tooltip: '更多',
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (v) async {
        switch (v) {
          case 'favorite':
            await toggleFavorite(context, entry);
          case 'wake':
            if (context.mounted) context.push('/wake');
          case 'forget':
            await toggleFavorite(context, entry);
            if (context.mounted) context.go('/');
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
            value: 'favorite', child: Text(entry.favorite ? '取消收藏' : '收藏')),
        if (target != null)
          const PopupMenuItem(value: 'wake', child: Text('远程开机设置')),
        if (entry.favorite && !entry.accountOwned && target == null)
          const PopupMenuItem(value: 'forget', child: Text('从列表移除')),
      ],
    );
  }
}
