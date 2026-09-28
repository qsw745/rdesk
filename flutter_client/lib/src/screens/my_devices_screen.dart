import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/device_directory_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/wake_provider.dart';
import '../ui/components.dart';
import '../ui/device_actions.dart';
import '../ui/tokens.dart';

class MyDevicesScreen extends StatefulWidget {
  final String initialFilter;
  const MyDevicesScreen({super.key, this.initialFilter = '全部'});
  @override
  State<MyDevicesScreen> createState() => _MyDevicesScreenState();
}

class _MyDevicesScreenState extends State<MyDevicesScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  late String _filter;
  String _query = '';
  bool _refreshing = false, _foreground = true;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _foreground && TickerMode.valuesOf(context).enabled) {
        unawaited(_refresh());
      }
    });
  }

  @override
  void didUpdateWidget(MyDevicesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFilter != widget.initialFilter) {
      _filter = widget.initialFilter;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && mounted && TickerMode.valuesOf(context).enabled) {
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    final auth = context.read<AuthProvider>();
    final wake = context.read<WakeProvider>();
    if (!auth.isLoggedIn) return;
    _refreshing = true;
    try {
      await Future.wait(
          [auth.refreshDevices(notifyOnStart: false), wake.refresh()]);
    } finally {
      _refreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final all = watchDeviceDirectory(context);
    final rows = all
        .where((e) =>
            (_filter != '在线' || e.online) &&
            (_filter != '收藏' || e.favorite) &&
            ('${e.name} ${e.deviceId}'
                .toLowerCase()
                .contains(_query.toLowerCase())))
        .toList();
    final online = all.where((e) => e.online).length;
    final wide = RdPage.wide(context);

    return RdPage(
      title: '我的设备',
      subtitle: all.isEmpty ? null : '共 ${all.length} 台 · $online 台在线',
      onRefresh: _refresh,
      maxWidth: 1180,
      actions: [
        IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新'),
        const SizedBox(width: 4),
        wide
            ? Tooltip(
                message: '添加设备',
                child: FilledButton.icon(
                    onPressed: () => showAddDeviceDialog(context),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('添加设备')),
              )
            : IconButton.filledTonal(
                onPressed: () => showAddDeviceDialog(context),
                icon: const Icon(Icons.add_rounded),
                tooltip: '添加设备'),
      ],
      children: [
        if (!auth.isLoggedIn) ...[
          _LoginBanner(onLogin: () => context.push('/login')),
          const SizedBox(height: Rd.s16),
        ],
        if (auth.error != null) ...[
          RdCard(
              color: RdPalette.of(context).dangerSoft,
              child: Text(auth.error!,
                  style: TextStyle(color: RdPalette.of(context).danger))),
          const SizedBox(height: Rd.s16),
        ],
        _Toolbar(
          filter: _filter,
          onFilter: (v) => setState(() => _filter = v),
          onQuery: (v) => setState(() => _query = v.trim()),
          showSearch: all.length > 4 || _query.isNotEmpty,
        ),
        const SizedBox(height: Rd.s16),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: RdEmptyState(
              icon: Icons.devices_rounded,
              title: _query.isNotEmpty
                  ? '没有匹配的设备'
                  : _filter == '全部'
                      ? '还没有设备'
                      : '没有$_filter设备',
              message: _query.isNotEmpty || _filter != '全部'
                  ? null
                  : '在另一台设备上登录同一账号即可自动出现，也可以输入设备码添加。',
              action: _query.isEmpty && _filter == '全部'
                  ? OutlinedButton.icon(
                      onPressed: () => showAddDeviceDialog(context),
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text('输入设备码添加'))
                  : null,
            ),
          )
        else
          LayoutBuilder(builder: (context, box) {
            final columns = box.maxWidth >= 1000
                ? 3
                : box.maxWidth >= 640
                    ? 2
                    : 1;
            if (columns == 1) {
              return Column(children: [
                for (final e in rows)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DeviceListCard(entry: e)),
              ]);
            }
            final width = (box.maxWidth - 16 * (columns - 1)) / columns;
            return Wrap(spacing: 16, runSpacing: 16, children: [
              for (final e in rows)
                SizedBox(width: width, child: DeviceGridCard(entry: e)),
            ]);
          }),
      ],
    );
  }
}

class _LoginBanner extends StatelessWidget {
  final VoidCallback onLogin;
  const _LoginBanner({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    final p = RdPalette.of(context);
    final t = Theme.of(context).textTheme;
    return RdCard(
      color: p.brandSoft,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(children: [
        Icon(Icons.cloud_sync_rounded, color: p.brand),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('登录后自动同步设备', style: t.titleSmall!.copyWith(color: p.brandInk)),
          const SizedBox(height: 2),
          Text('同一账号下的电脑和手机会自动出现在这里，无需记设备码。',
              style: t.bodySmall!.copyWith(color: p.brandInk)),
        ])),
        const SizedBox(width: 8),
        FilledButton(onPressed: onLogin, child: const Text('登录')),
      ]),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final String filter;
  final ValueChanged<String> onFilter, onQuery;
  final bool showSearch;
  const _Toolbar(
      {required this.filter,
      required this.onFilter,
      required this.onQuery,
      required this.showSearch});

  @override
  Widget build(BuildContext context) {
    final chips = Wrap(spacing: 8, children: [
      for (final v in const ['全部', '在线', '收藏'])
        ChoiceChip(
            label: Text(v),
            selected: filter == v,
            onSelected: (_) => onFilter(v)),
    ]);
    final search = TextField(
      onChanged: onQuery,
      decoration: const InputDecoration(
          hintText: '搜索名称或设备码',
          prefixIcon: Icon(Icons.search_rounded, size: 20),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 10)),
    );
    if (!showSearch) {
      return Align(alignment: Alignment.centerLeft, child: chips);
    }
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < 560) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          search,
          const SizedBox(height: 12),
          chips,
        ]);
      }
      return Row(children: [
        chips,
        const Spacer(),
        SizedBox(width: 280, child: search),
      ]);
    });
  }
}

/// Primary action for a device card: connect when controllable and online,
/// wake when it is a configured wake target and offline.
Widget? _primaryAction(BuildContext context, DeviceDirectoryEntry e,
    {bool compact = false}) {
  final abilities = DeviceAbilities.of(context, e);
  final wake = context.watch<WakeProvider>();
  final target = e.wakeTarget;
  final waking = target != null &&
      (wake.history[target.id]?.any((r) => r.active) ?? false);
  if (!e.online && abilities.canWake && target != null) {
    final p = RdPalette.of(context);
    return FilledButton.icon(
      style: FilledButton.styleFrom(
          backgroundColor: p.power,
          minimumSize: Size(compact ? 64 : 88, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14)),
      onPressed: waking || wake.busy ? null : () => wakeDevice(context, target),
      icon: const Icon(Icons.power_settings_new_rounded, size: 18),
      label: Text(waking ? '开机中' : '开机'),
    );
  }
  if (canConnectNow(e, abilities)) {
    return ValueListenableBuilder<String?>(
      valueListenable: connectingDevice,
      builder: (context, key, _) => FilledButton(
        style: FilledButton.styleFrom(
            minimumSize: Size(compact ? 64 : 88, 36),
            padding: const EdgeInsets.symmetric(horizontal: 16)),
        onPressed: key != null ? null : () => connectToDevice(context, e),
        child: Text(key == e.key ? '连接中…' : '连接'),
      ),
    );
  }
  return null;
}

String _subtitle(
    DeviceDirectoryEntry e, String status, DeviceAbilities abilities) {
  final platform = rdPlatformOf(e.platform);
  final wakeable = e.wakeTarget?.setupComplete == true;
  final parts = [
    status,
    if (platform != RdPlatform.unknown) platform.label,
    if (abilities.isLocal) '本机',
    if (wakeable && !e.online) '可远程开机',
    if (!abilities.canControl && !abilities.isLocal && !(wakeable && !e.online))
      '暂不支持被远程控制',
  ];
  return parts.join(' · ');
}

class DeviceListCard extends StatelessWidget {
  final DeviceDirectoryEntry entry;
  const DeviceListCard({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final p = RdPalette.of(context);
    final t = Theme.of(context).textTheme;
    final status = deviceStatus(entry, context.watch<WakeProvider>());
    final action = _primaryAction(context, entry, compact: true);
    return RdCard(
      onTap: () => context.push(devicePath(entry)),
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      child: Row(children: [
        RdDeviceGlyph(platform: entry.platform, online: entry.online),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                  child: Text(entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleMedium)),
              if (entry.favorite) ...[
                const SizedBox(width: 4),
                Icon(Icons.star_rounded, size: 16, color: p.warning),
              ],
            ]),
            const SizedBox(height: 3),
            Text(
                _subtitle(
                    entry, status.label, DeviceAbilities.of(context, entry)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall!.copyWith(
                    color: status.tone == RdTone.neutral
                        ? p.inkTertiary
                        : status.tone.fg(p))),
          ]),
        ),
        const SizedBox(width: 10),
        action ?? Icon(Icons.chevron_right_rounded, color: p.inkTertiary),
      ]),
    );
  }
}

class DeviceGridCard extends StatelessWidget {
  final DeviceDirectoryEntry entry;
  const DeviceGridCard({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final p = RdPalette.of(context);
    final t = Theme.of(context).textTheme;
    final status = deviceStatus(entry, context.watch<WakeProvider>());
    final action = _primaryAction(context, entry);
    final platform = rdPlatformOf(entry.platform);
    return RdCard(
      onTap: () => context.push(devicePath(entry)),
      padding: const EdgeInsets.all(18),
      radius: Rd.radiusLg,
      child: SizedBox(
        height: 172,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RdDeviceGlyph(
                platform: entry.platform, size: 48, online: entry.online),
            const Spacer(),
            if (entry.favorite)
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 2),
                child: Icon(Icons.star_rounded, size: 18, color: p.warning),
              ),
            RdStatusPill(status.label, tone: status.tone),
          ]),
          const SizedBox(height: 16),
          Text(entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.titleMedium),
          const SizedBox(height: 4),
          Text(
              [
                if (platform != RdPlatform.unknown) platform.label,
                formatDeviceId(entry.deviceId),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodySmall!.copyWith(color: p.inkTertiary)),
          const Spacer(),
          Row(children: [
            Expanded(
              child: Text(
                  entry.wakeTarget?.setupComplete == true
                      ? '已开启远程开机'
                      : DeviceAbilities.of(context, entry).unsupportedReason ??
                          (entry.online
                              ? '可以连接'
                              : statusKnown(entry)
                                  ? '等待设备上线'
                                  : '输入对方验证码即可连接'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelSmall),
            ),
            if (action != null) action,
          ]),
        ]),
      ),
    );
  }
}
