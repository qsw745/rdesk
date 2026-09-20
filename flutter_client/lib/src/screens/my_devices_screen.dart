import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/device_directory_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/address_book_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/wake_provider.dart';
import '../utils/device_directory.dart';

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
    if (_foreground && mounted && TickerMode.valuesOf(context).enabled)
      unawaited(_refresh());
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

  Future<void> _connect(DeviceDirectoryEntry item) async {
    final current = normalizedEndpointScope(
        context.read<SettingsProvider>().signalingServer);
    if (item.endpointScope != null && item.endpointScope != current) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('这台设备属于另一台服务器，请先在网络设置中切换服务器。')));
      return;
    }
    if (item.endpointScope == null) {
      final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: const Text('确认连接来源'),
                  content: const Text('这是旧版本保存的设备，未记录服务器。使用当前服务器查找此设备？'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('继续连接'))
                  ]));
      if (confirm != true || !mounted) return;
    }
    context.read<ConnectionProvider>().prepareQuickConnect(item.deviceId);
    context.go('/assist');
  }

  Future<void> _favorite(DeviceDirectoryEntry item) async {
    final book = context.read<AddressBookProvider>();
    if (item.favorite) {
      await book.removeEntry(item.deviceId, endpointScope: item.endpointScope);
    } else {
      await book.addEntry(
          deviceId: item.deviceId,
          alias: item.name,
          platform: item.platform,
          endpointScope: item.endpointScope);
    }
  }

  Future<void> _add() async {
    final id = TextEditingController(), alias = TextEditingController();
    final book = context.read<AddressBookProvider>();
    final scope = normalizedEndpointScope(
        context.read<SettingsProvider>().signalingServer);
    await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('添加设备'),
                content: SizedBox(
                    width: 360,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: id,
                          autofocus: true,
                          decoration:
                              const InputDecoration(labelText: '设备 ID 或直连地址')),
                      const SizedBox(height: 16),
                      TextField(
                          controller: alias,
                          decoration:
                              const InputDecoration(labelText: '备注名称（可选）')),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () async {
                        if (id.text.trim().isEmpty) return;
                        await book.addEntry(
                            deviceId: id.text.trim(),
                            alias: alias.text.trim(),
                            endpointScope: scope);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('保存到收藏'))
                ]));
    // Let the closing route finish using its editing controllers.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    id.dispose();
    alias.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final connection = context.watch<ConnectionProvider>();
    final book = context.watch<AddressBookProvider>();
    final wake = context.watch<WakeProvider>();
    final scope = context.watch<SettingsProvider>().signalingServer;
    final rows = mergeDeviceDirectory(
            endpointScope: scope,
            accountDevices: normalizedEndpointScope(auth.devicesEndpoint) ==
                    normalizedEndpointScope(scope)
                ? auth.devices
                : const [],
            history: connection.recentConnections,
            saved: book.allEntries,
            wakeTargets: wake.targets)
        .where((e) =>
            (_filter != '在线' || e.online) &&
            (_filter != '收藏' || e.favorite) &&
            ('${e.name} ${e.deviceId}'
                .toLowerCase()
                .contains(_query.toLowerCase())))
        .toList();
    final mobile = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
    return Scaffold(
        appBar: AppBar(
            title: const Text('我的设备'),
            automaticallyImplyLeading: false,
            actions: [
              if (mobile)
                IconButton(
                    onPressed: () => context.push('/wake/scan'),
                    icon: const Icon(Icons.qr_code_scanner),
                    tooltip: '扫码添加电脑'),
              IconButton(
                  onPressed: _add,
                  icon: const Icon(Icons.add),
                  tooltip: '添加设备'),
              PopupMenuButton<String>(
                  tooltip: '更多设备操作',
                  onSelected: (v) => context.push(v),
                  itemBuilder: (_) => const [
                        PopupMenuItem(value: '/wake', child: Text('远程开机')),
                        PopupMenuItem(value: '/saved', child: Text('管理收藏和分组')),
                      ]),
              const SizedBox(width: 12),
            ]),
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
              child: Column(children: [
                TextField(
                    onChanged: (v) => setState(() => _query = v.trim()),
                    decoration: const InputDecoration(
                        hintText: '搜索名称或设备 ID',
                        prefixIcon: Icon(Icons.search),
                        isDense: true)),
                const SizedBox(height: 12),
                Row(children: [
                  for (final value in ['全部', '在线', '收藏'])
                    Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                            label: Text(value),
                            selected: _filter == value,
                            onSelected: (_) =>
                                setState(() => _filter = value))),
                  const Spacer(),
                  IconButton(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      tooltip: '刷新设备'),
                ]),
              ])),
          if (!auth.isLoggedIn)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(children: [
                  const Expanded(
                      child: Text('登录后同步其他设备', style: TextStyle(fontSize: 13))),
                  TextButton(
                      onPressed: () => context.push('/login'),
                      child: const Text('登录账号')),
                ])),
          if (auth.error != null)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(auth.error!)),
          Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.devices_outlined,
                          size: 48,
                          color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 16),
                      Text(_query.isNotEmpty
                          ? '没有匹配的设备'
                          : '暂无${_filter == '全部' ? '' : _filter}设备'),
                      const SizedBox(height: 8),
                      const Text('添加设备，或登录同一账号同步',
                          style: TextStyle(fontSize: 13)),
                    ]))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _device(rows[i], wake))),
        ]));
  }

  Widget _device(DeviceDirectoryEntry item, WakeProvider wake) {
    final target = item.wakeTarget;
    final windows = item.platform.toLowerCase().contains('windows');
    final source = item.endpointScope == null ? ' · 来源未记录' : '';
    final status = target != null && !target.setupComplete
        ? '已配对 · 待完成开机设置'
        : item.online
            ? '在线'
            : target != null
                ? (target.agentOnline ? '助手在线 · 可发送开机信号' : '家中助手离线')
                : '未确认在线';
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(18),
            child: LayoutBuilder(builder: (context, box) {
              final info = Row(children: [
                Icon(
                    windows
                        ? Icons.desktop_windows_outlined
                        : Icons.devices_outlined,
                    size: 30),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(item.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 16)),
                      const SizedBox(height: 6),
                      Text('$status$source',
                          style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 3),
                      Text(item.deviceId, style: const TextStyle(fontSize: 13)),
                    ])),
              ]);
              final actions = Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    IconButton(
                        onPressed: () => _favorite(item),
                        tooltip: item.favorite ? '取消收藏' : '收藏设备',
                        icon: Icon(item.favorite
                            ? Icons.star_rounded
                            : Icons.star_border_rounded)),
                    if (target != null && !target.setupComplete)
                      FilledButton.tonal(
                          onPressed: () => context.push(
                              '/wake/target/${Uri.encodeComponent(target.id)}'),
                          child: const Text('继续配置')),
                    if (target != null &&
                        target.setupComplete &&
                        !target.online)
                      FilledButton(
                          onPressed: !target.agentOnline || wake.busy
                              ? null
                              : () async {
                                  final ok = await wake.wake(target);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(ok
                                              ? '开机请求已提交，可在远程开机中查看进度'
                                              : wake.error ?? '开机请求失败')));
                                },
                          child: const Text('开机')),
                    if (!windows)
                      FilledButton.tonal(
                          onPressed: () => _connect(item),
                          child: const Text('连接')),
                  ]);
              return box.maxWidth < 520
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                          info,
                          const SizedBox(height: 12),
                          Align(
                              alignment: Alignment.centerRight, child: actions)
                        ])
                  : Row(children: [
                      Expanded(child: info),
                      const SizedBox(width: 16),
                      actions
                    ]);
            })));
  }
}
