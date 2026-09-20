import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../providers/wake_provider.dart';
import '../providers/wake_pairing_provider.dart';
import '../providers/connection_provider.dart';
import '../services/windows_wake_service.dart';

class WindowsWakeScreen extends StatefulWidget {
  const WindowsWakeScreen({super.key});
  @override
  State<WindowsWakeScreen> createState() => _WindowsWakeScreenState();
}

class _WindowsWakeScreenState extends State<WindowsWakeScreen>
    with WidgetsBindingObserver {
  final _name = TextEditingController(text: Platform.localHostname);
  WindowsAdapterScan? _scan;
  WindowsWakeAdapter? _selected;
  WindowsWakeCheck? _check;
  bool _detecting = false, _foreground = true;
  bool? _startup;
  String? _error;
  int _generation = 0;
  WakeProvider? _wake;
  ValueListenable<TickerModeData>? _ticker;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _wake = context.read<WakeProvider>();
        _visibility();
        unawaited(_detect());
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ticker = TickerMode.getValuesNotifier(context);
    if (_ticker != ticker) {
      _ticker?.removeListener(_visibility);
      _ticker = ticker;
      _ticker!.addListener(_visibility);
    }
    _visibility();
  }

  void _visibility() {
    _wake?.pairing?.setVisible(_foreground && (_ticker?.value.enabled ?? true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _visibility();
  }

  @override
  void dispose() {
    _generation++;
    _wake?.pairing?.setVisible(false);
    _ticker?.removeListener(_visibility);
    WidgetsBinding.instance.removeObserver(this);
    _name.dispose();
    super.dispose();
  }

  Future<void> _detect() async {
    final service = _wake?.windows;
    if (service == null) return;
    final gen = ++_generation;
    setState(() {
      _detecting = true;
      _error = null;
      _check = null;
    });
    final scan = await service.scanAdapters();
    if (!mounted || gen != _generation) return;
    final wired = scan.adapters.where((a) => a.wired && a.connected).toList();
    setState(() {
      _scan = scan;
      _selected = wired.where((a) => a.id == _selected?.id).firstOrNull ??
          (wired.length == 1 ? wired.first : null);
      _detecting = false;
    });
    try {
      final startup = await service.loginStartupEnabled();
      if (mounted && gen == _generation) setState(() => _startup = startup);
    } catch (_) {
      if (mounted && gen == _generation)
        setState(() => _error = '无法读取登录启动设置，可在 Windows 启动应用中检查');
    }
    await _inspect(gen);
  }

  Future<void> _inspect(int gen) async {
    final selected = _selected;
    if (selected == null) return;
    try {
      final check = await _wake!.windows!.inspect(selected.mac);
      if (mounted && gen == _generation) setState(() => _check = check);
    } catch (_) {
      if (mounted && gen == _generation)
        setState(() => _error = '网卡已识别。驱动唤醒设置需在设备管理器中核对。');
    }
  }

  Widget _card(String title, List<Widget> children) => Card(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            ...children
          ])));
  Future<void> _start(WakePairingProvider pairing) async {
    final selected = _selected;
    if (selected == null) return;
    final local = await context.read<ConnectionProvider>().getLocalDevice();
    if (!mounted) return;
    if (local == null) {
      setState(() => _error = '无法读取本机设备编号，请重启 RDesk 后重试');
      return;
    }
    await pairing.start(
        name: _name.text.trim(), deviceId: local.deviceId, mac: selected.mac);
  }

  @override
  Widget build(BuildContext context) {
    final wake = context.watch<WakeProvider>();
    final pairing = wake.pairing;
    return Scaffold(
        appBar: AppBar(title: const Text('远程开机')),
        body: !wake.loggedIn
            ? Center(
                child: FilledButton(
                    onPressed: () => context.push('/login?redirect=/wake'),
                    child: const Text('登录后配置这台电脑')))
            : pairing == null
                ? const Center(child: Text('请在 Windows 电脑上配置本机开机'))
                : ListenableBuilder(
                    listenable: pairing,
                    builder: (context, _) => SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                            child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 1040),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('让这台电脑随时待命',
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineMedium),
                                      const SizedBox(height: 8),
                                      const Text(
                                          '检测网卡后，用 iPhone 或安卓手机扫码，完成家中助手和开机设置。'),
                                      const SizedBox(height: 24),
                                      LayoutBuilder(builder: (context, size) {
                                        final local = _localCard(pairing);
                                        final pair = _pairCard(pairing, wake);
                                        return size.maxWidth >= 800
                                            ? Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                    Expanded(child: local),
                                                    const SizedBox(width: 16),
                                                    Expanded(child: pair)
                                                  ])
                                            : Column(children: [
                                                local,
                                                const SizedBox(height: 12),
                                                pair
                                              ]);
                                      }),
                                      const SizedBox(height: 16),
                                      const Text(
                                          '电脑需插网线、保持供电。外出开机还需要一台留在家中 Wi-Fi 下的安卓手机。'),
                                    ]))))));
  }

  Widget _localCard(WakePairingProvider pairing) => _card('1. 检查这台电脑', [
        TextField(
            controller: _name,
            maxLength: 40,
            decoration:
                const InputDecoration(labelText: '电脑名称', counterText: '')),
        const SizedBox(height: 16),
        if (_detecting) const LinearProgressIndicator(),
        Text(_detecting ? '正在检测有线网卡' : _scan?.message ?? '准备检测有线网卡'),
        const SizedBox(height: 12),
        if (_scan != null && _scan!.adapters.where((a) => a.wired).isNotEmpty)
          DropdownButtonFormField<String>(
              initialValue: _selected?.id,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '有线网卡'),
              items: _scan!.adapters
                  .where((a) => a.wired)
                  .map((a) => DropdownMenuItem(
                      value: a.id,
                      enabled: a.connected,
                      child: Text('${a.name}${a.connected ? '' : ' · 未连接'}',
                          overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: pairing.busy
                  ? null
                  : (id) {
                      setState(() {
                        _selected =
                            _scan!.adapters.firstWhere((a) => a.id == id);
                        _check = null;
                      });
                      unawaited(_inspect(++_generation));
                    }),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          TextButton.icon(
              onPressed: _detecting ? null : _detect,
              icon: const Icon(Icons.refresh),
              label: const Text('重新检测')),
          if (_scan != null)
            TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _scan!.diagnostic));
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制诊断，不含完整网卡地址')));
                },
                child: const Text('复制诊断'))
        ]),
        ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('网卡唤醒设置'),
            children: [
              for (final item in [
                ('魔术包唤醒', _check?.magicPacket),
                ('允许此设备唤醒电脑', _check?.wakeArmed),
                ('关机网络唤醒', _check?.shutdownWake)
              ])
                ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(item.$2 == WakeCheckState.enabled
                        ? Icons.check_circle_outline
                        : Icons.info_outline),
                    title: Text(item.$1),
                    subtitle: Text(item.$2 == WakeCheckState.enabled
                        ? '已开启'
                        : item.$2 == WakeCheckState.disabled
                            ? '请开启'
                            : '请手动核对')),
              TextButton(
                  onPressed: () async {
                    try {
                      await _wake!.windows!.openDeviceManager();
                    } catch (_) {
                      if (mounted) setState(() => _error = '请在开始菜单打开设备管理器');
                    }
                  },
                  child: const Text('打开设备管理器'))
            ]),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('登录 Windows 后启动 RDesk'),
            subtitle: const Text('用于确认电脑已上线'),
            value: _startup ?? false,
            onChanged: _startup == null
                ? null
                : (value) async {
                    try {
                      await _wake!.windows!.setLoginStartup(value);
                      if (mounted) setState(() => _startup = value);
                    } catch (_) {
                      if (mounted) setState(() => _error = '保存登录启动设置失败，请重试');
                    }
                  }),
        if (_error != null)
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ]);
  Widget _pairCard(WakePairingProvider p, WakeProvider wake) {
    if (p.phase == PairingPhase.paired) {
      final target = wake.targets.where((t) => t.id == p.targetId).firstOrNull;
      return _card('2. 已与手机配对', [
        const Icon(Icons.check_circle_outline,
            size: 64, color: Color(0xff267647)),
        const SizedBox(height: 16),
        Text(target?.setupComplete == true
            ? '配置已保存，可以在手机上测试开机。'
            : '请在手机上继续选择家中助手、核对 BIOS 并测试。'),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: wake.refresh, child: const Text('刷新配置状态'))
      ]);
    }
    final waiting = p.session != null &&
        p.phase != PairingPhase.expired &&
        p.phase != PairingPhase.failed;
    return _card('2. 手机扫码配对', [
      if (waiting) ...[
        Center(
            child: QrImageView(
                data: p.session!.qrText,
                size: 216,
                backgroundColor: Colors.white)),
        const SizedBox(height: 12),
        const Text('手机打开 RDesk → 设备 → 扫码添加\n请使用与电脑相同的账号',
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        SelectableText(p.session!.manualCode,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: 2)),
        const SizedBox(height: 6),
        Text('无法扫码时，可在手机输入上方配对码 · ${p.secondsRemaining} 秒后失效',
            textAlign: TextAlign.center),
        if (p.phase == PairingPhase.claiming)
          const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text('手机已确认，正在安全保存配对…', textAlign: TextAlign.center))
      ] else ...[
        const Icon(Icons.qr_code_2, size: 72, color: Color(0xff526074)),
        const SizedBox(height: 20),
        const Text('手机确认后，这台电脑会加入你的设备列表。', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton(
            onPressed: p.busy || _selected == null ? null : () => _start(p),
            child: Text(p.busy
                ? '正在准备…'
                : p.phase == PairingPhase.expired
                    ? '重新生成配对码'
                    : '生成配对二维码'))
      ],
      if (p.error != null) ...[
        const SizedBox(height: 12),
        Text(p.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
        TextButton(
            onPressed: p.busy ? null : p.poll, child: const Text('重试当前配对'))
      ],
    ]);
  }
}
