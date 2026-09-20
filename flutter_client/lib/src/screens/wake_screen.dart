import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/wake.dart';
import '../providers/wake_provider.dart';
import '../services/rdesk_bridge_service.dart';
import '../services/windows_wake_service.dart';

String _time(int? ms) => ms == null
    ? '未收到'
    : DateTime.fromMillisecondsSinceEpoch(ms)
        .toLocal()
        .toString()
        .split('.')
        .first;

Widget _panel(List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children)));

Widget _notice(String text, {bool error = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child:
        Text(text, style: TextStyle(color: error ? Colors.deepOrange : null)));

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
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _wake?.setVisible(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    _wake?.setVisible(false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _setup(WakeProvider wake) async {
    wake.setVisible(false);
    await context.push('/wake/setup');
    if (mounted) wake.setVisible(true);
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
          : Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: RefreshIndicator(
                      onRefresh: wake.refresh,
                      child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(20),
                          children: [
                            if (wake.error != null)
                              _panel([
                                const Text('暂时无法连接开机服务',
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                                _notice(wake.error!, error: true),
                                TextButton(
                                    onPressed: wake.refresh,
                                    child: const Text('重新检测')),
                              ]),
                            if (wake.targets.isEmpty)
                              _panel([
                                const Icon(Icons.desktop_windows_rounded,
                                    size: 64, color: Color(0xff3979ff)),
                                const SizedBox(height: 20),
                                const Text('随时开启家中电脑',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 12),
                                const Text('首次配置一次，以后点一下就能发起开机。',
                                    textAlign: TextAlign.center),
                                const SizedBox(height: 24),
                                FilledButton(
                                    onPressed: () => _setup(wake),
                                    child: Text(wake.windows != null
                                        ? '启用远程开机'
                                        : '开始配置')),
                              ]),
                            for (final target in wake.targets)
                              _target(wake, target),
                            if (wake.targets.isNotEmpty)
                              TextButton.icon(
                                  onPressed: () => _setup(wake),
                                  icon: const Icon(Icons.settings_outlined),
                                  label: const Text('配置远程开机')),
                            if (defaultTargetPlatform == TargetPlatform.android)
                              _panel([
                                SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('作为家中开机助手'),
                                    subtitle: Text(wake.helper.enabled
                                        ? '保持本机在家中 Wi-Fi，并持续供电'
                                        : '将这台安卓手机留在家中，代发开机信号'),
                                    value: wake.helper.enabled,
                                    onChanged: wake.busy
                                        ? null
                                        : (v) async {
                                            if (v) {
                                              await _setup(wake);
                                            } else {
                                              await wake.disableHelper();
                                            }
                                          }),
                              ]),
                          ])))),
    );
  }

  Widget _target(WakeProvider wake, WakeTarget target) {
    final requests = wake.history[target.id] ?? [];
    final pending = requests.any((r) => r.active);
    return _panel([
      Row(children: [
        const Icon(Icons.desktop_windows_rounded,
            size: 36, color: Color(0xff3979ff)),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(target.name, style: Theme.of(context).textTheme.titleLarge),
          Text(target.online
              ? '电脑应用在线'
              : target.agentOnline
                  ? '可发送开机信号'
                  : '家中助手离线'),
        ])),
        IconButton(
            tooltip: '更多',
            icon: const Icon(Icons.more_horiz),
            onPressed: () => _details(wake, target)),
      ]),
      if (requests.isNotEmpty) _notice(wakePhaseLabel(requests.first.phase)),
      if (!target.agentOnline) _notice('请检查留在家中的安卓手机是否联网、开机助手是否开启。'),
      if (requests.isNotEmpty && requests.first.phase == WakePhase.unconfirmed)
        _notice('尚未收到电脑应用的上线信号。电脑可能已启动，请确认 RDesk 已运行；也可在“更多”查看记录。'),
      const SizedBox(height: 16),
      FilledButton.icon(
          onPressed:
              wake.busy || target.online || !target.agentOnline || pending
                  ? null
                  : () => wake.wake(target),
          icon: const Icon(Icons.power_settings_new),
          label: Text(target.online
              ? '电脑已在线'
              : pending
                  ? '正在开机…'
                  : '开机')),
    ]);
  }

  Future<void> _details(WakeProvider wake, WakeTarget target) =>
      showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (sheet) => ChangeNotifierProvider<WakeProvider>.value(
              value: wake,
              child: Consumer<WakeProvider>(builder: (_, current, __) {
                final requests = current.history[target.id] ?? [];
                final helper = current.agents
                    .where((a) => a.id == target.agentId)
                    .firstOrNull;
                return SafeArea(
                    child: SizedBox(
                        height: MediaQuery.sizeOf(sheet).height * .75,
                        child: ListView(
                            padding: const EdgeInsets.all(20),
                            children: [
                              Text(target.name,
                                  style: Theme.of(sheet).textTheme.titleLarge),
                              Text(
                                  '助手：${helper?.name ?? '未找到'} · 最近在线：${_time(helper?.lastSeenMs)}'),
                              ExpansionTile(
                                  title: const Text('查看记录'),
                                  initiallyExpanded: true,
                                  children: [
                                    if (requests.isEmpty)
                                      const ListTile(title: Text('暂无开机记录')),
                                    for (final r in requests)
                                      ListTile(
                                          title: Text(wakePhaseLabel(r.phase)),
                                          subtitle: Text(
                                              '提交：${_time(r.createdAtMs)}\n领取：${_time(r.claimedAtMs)}\n发送回执：${_time(r.sentAtMs)}\n电脑上线：${_time(r.onlineAtMs)}${r.errorCode == null ? '' : '\n诊断代码：${r.errorCode}'}')),
                                    const Text('保留最近 7 天、最多 50 条记录。'),
                                  ]),
                              TextButton(
                                  onPressed: current.busy
                                      ? null
                                      : () async {
                                          final id = await showDialog<String>(
                                              context: sheet,
                                              builder: (dialog) => SimpleDialog(
                                                      title:
                                                          const Text('更换家中助手'),
                                                      children: [
                                                        for (final a in current
                                                            .agents
                                                            .where((a) =>
                                                                a.enabled))
                                                          SimpleDialogOption(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                      dialog,
                                                                      a.id),
                                                              child: Text(
                                                                  '${a.name} · ${a.online ? '在线' : '离线'}')),
                                                        if (!current.agents.any(
                                                            (a) => a.enabled))
                                                          const Padding(
                                                              padding:
                                                                  EdgeInsets
                                                                      .all(20),
                                                              child: Text(
                                                                  '请先在家中安卓手机启用助手')),
                                                      ]));
                                          if (id != null) {
                                            await current.rebind(target, id);
                                          }
                                        },
                                  child: const Text('更换助手')),
                              TextButton(
                                  onPressed: current.busy
                                      ? null
                                      : () async {
                                          final confirmed = await showDialog<
                                                  bool>(
                                              context: sheet,
                                              builder: (dialog) => AlertDialog(
                                                      title:
                                                          const Text('移除开机配置？'),
                                                      content: Text(
                                                          '将移除“${target.name}”的开机配置，并取消未完成的请求。'),
                                                      actions: [
                                                        TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                    dialog,
                                                                    false),
                                                            child: const Text(
                                                                '取消')),
                                                        TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                    dialog,
                                                                    true),
                                                            child: const Text(
                                                                '移除'))
                                                      ]));
                                          if (confirmed == true &&
                                              await current.remove(target) &&
                                              sheet.mounted) {
                                            Navigator.pop(sheet);
                                          }
                                        },
                                  child: const Text('移除电脑')),
                              if (current.error != null)
                                _notice(current.error!, error: true),
                            ])));
              })));
}

class WakeSetupScreen extends StatefulWidget {
  const WakeSetupScreen({super.key});
  @override
  State<WakeSetupScreen> createState() => _WakeSetupScreenState();
}

class _WakeSetupScreenState extends State<WakeSetupScreen>
    with WidgetsBindingObserver {
  WakeProvider? _wake;
  final _name = TextEditingController();
  final _scroll = ScrollController();
  List<WindowsWakeAdapter> _adapters = [];
  WindowsWakeAdapter? _adapter;
  WindowsWakeCheck? _check;
  String? _agentId, _error, _checkError;
  int _step = 0, _generation = 0;
  bool _biosConfirmed = false, _sameNetwork = false, _startup = true;
  bool _loading = true, _saving = false, _saved = false;
  bool get _android => defaultTargetPlatform == TargetPlatform.android;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _name.text = _android ? '家中安卓手机' : Platform.localHostname;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _wake = context.read<WakeProvider>();
        _wake!.setVisible(true);
        unawaited(_load());
      }
    });
  }

  WakeAgent? _selectedAgent(WakeProvider wake) {
    final agents = wake.agents.where((a) => a.enabled && a.online).toList();
    final selected = agents.where((a) => a.id == _agentId).firstOrNull;
    if (_agentId != null) return selected;
    return agents.length == 1 ? agents.single : null;
  }

  Future<void> _load() async {
    final gen = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _checkError = null;
      _check = null;
    });
    final wake = context.read<WakeProvider>();
    try {
      await wake.refresh();
      final adapters = await wake.windows?.adapters() ?? [];
      if (!mounted || gen != _generation) return;
      _adapters = adapters.where((a) => a.connected && a.wired).toList();
      _adapter = _adapters.where((a) => a.mac == _adapter?.mac).firstOrNull ??
          _adapters.firstOrNull;
      if (_adapter != null && wake.windows != null) {
        try {
          _check = await wake.windows!.inspect(_adapter!.mac);
        } catch (_) {
          _checkError = '驱动未提供完整检测信息，请在设备管理器中核对。';
        }
      }
    } catch (_) {
      _error = '无法读取网卡，请检查网线连接后重新检测。';
    } finally {
      if (mounted && gen == _generation) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _wake?.setVisible(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    ++_generation;
    _wake?.setVisible(false);
    WidgetsBinding.instance.removeObserver(this);
    _name.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _go(int step) {
    setState(() {
      _step = step;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Widget _status(String title, String detail, {bool? ok}) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
          ok == true
              ? Icons.check_circle
              : ok == false
                  ? Icons.error_outline
                  : Icons.help_outline,
          color: ok == true
              ? Colors.green
              : ok == false
                  ? Colors.deepOrange
                  : Colors.blueGrey),
      title: Text(title),
      subtitle: Text(detail));
  Widget _checkRow(String title, WakeCheckState? state) => _status(
      title,
      state == WakeCheckState.enabled
          ? '已开启'
          : state == WakeCheckState.disabled
              ? '未开启，请在设备管理器中设置'
              : '无法自动判断',
      ok: state == WakeCheckState.enabled
          ? true
          : state == WakeCheckState.disabled
              ? false
              : null);
  @override
  Widget build(BuildContext context) {
    final wake = context.watch<WakeProvider>();
    final windows = wake.windows != null;
    return Scaffold(
        appBar: AppBar(
            title: Text(windows
                ? '配置远程开机'
                : _android
                    ? '家中开机助手'
                    : '配置远程开机')),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: !wake.loggedIn
                    ? Center(
                        child: FilledButton(
                            onPressed: () =>
                                context.push('/login?redirect=/wake/setup'),
                            child: const Text('登录账号')))
                    : ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.all(20),
                        children: [
                            if (windows) ...[
                              Row(children: [
                                for (var i = 0; i < 3; i++)
                                  Expanded(
                                      child: Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 24),
                                          child: Text(
                                              '${i + 1} ${[
                                                '检测设备',
                                                'BIOS 设置',
                                                '开机测试'
                                              ][i]}',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: i <= _step
                                                      ? const Color(0xff3979ff)
                                                      : Colors.grey))))
                              ]),
                              if (_step == 0) ..._detect(wake),
                              if (_step == 1) ..._bios(),
                              if (_step == 2) ..._test(wake),
                            ] else if (_android)
                              ..._helper(wake)
                            else
                              _panel([
                                const Icon(Icons.desktop_windows,
                                    size: 56, color: Color(0xff3979ff)),
                                const SizedBox(height: 16),
                                const Text('先在 Windows 电脑完成一次配置',
                                    style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 12),
                                const Text(
                                    '电脑和留在家中的安卓手机登录同一账号。电脑进入“远程开机”，手机启用“家中开机助手”。配置完成后，这里就会出现电脑和开机按钮。'),
                                TextButton(
                                    onPressed: () => context.pop(),
                                    child: const Text('返回电脑列表')),
                              ]),
                            if (_error != null || wake.error != null)
                              _notice(_error ?? wake.error!, error: true),
                          ]))));
  }

  List<Widget> _detect(WakeProvider wake) {
    final helper = _selectedAgent(wake);
    final helpers = wake.agents.where((a) => a.enabled && a.online).toList();
    return [
      _panel([
        const Text('检测网络唤醒设置',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('请把电脑网线接到家中路由器，并保持电源接通。'),
        if (_loading)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: LinearProgressIndicator())
        else ...[
          _status('有线网卡', _adapter?.name ?? '未找到已连接的有线网卡',
              ok: _adapter != null),
          if (_adapter != null) ...[
            _checkRow('魔术包唤醒', _check?.magicPacket),
            _checkRow('允许网卡唤醒电脑', _check?.wakeArmed),
            _checkRow('关机网络唤醒', _check?.shutdownWake),
          ],
          if (_checkError != null) _notice(_checkError!),
          if (_check?.allEnabled != true && _adapter != null)
            TextButton.icon(
                onPressed: () async {
                  try {
                    await wake.windows!.openDeviceManager();
                  } catch (_) {
                    if (mounted) {
                      setState(() {
                        _error = '请在开始菜单打开设备管理器，进入网卡属性。';
                      });
                    }
                  }
                },
                icon: const Icon(Icons.settings_outlined),
                label: const Text('打开设备管理器')),
        ],
      ]),
      _panel([
        const Text('连接家中安卓手机',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        _status(
            '开机助手', helper?.name ?? (helpers.isEmpty ? '等待家中手机上线' : '请选择家中手机'),
            ok: helper != null),
        if (helper == null && helpers.isEmpty)
          const Text('在留在家中的安卓手机上登录同一账号，进入“远程开机”，启用“家中开机助手”。'),
        if (helpers.length > 1 ||
            (_agentId != null && helper == null && helpers.isNotEmpty))
          DropdownButtonFormField<String>(
              initialValue: helper?.id,
              decoration: const InputDecoration(labelText: '选择家中手机'),
              items: [
                for (final a in helpers)
                  DropdownMenuItem(value: a.id, child: Text(a.name))
              ],
              onChanged: (id) => setState(() {
                    _agentId = id;
                    _sameNetwork = false;
                  })),
        const SizedBox(height: 8),
        const Text('手机必须与电脑连接同一家庭网络，不能使用访客 Wi-Fi。在线状态不代表已确认同一局域网。'),
      ]),
      ExpansionTile(title: const Text('电脑名称与网卡'), children: [
        TextField(
            controller: _name,
            maxLength: 40,
            decoration: const InputDecoration(labelText: '电脑名称')),
        if (_adapters.length > 1)
          DropdownButtonFormField<String>(
              initialValue: _adapter?.mac,
              items: [
                for (final a in _adapters)
                  DropdownMenuItem(
                      value: a.mac, child: Text('${a.name} · ${a.mac}'))
              ],
              onChanged: _loading
                  ? null
                  : (mac) {
                      _adapter = _adapters.firstWhere((a) => a.mac == mac);
                      unawaited(_load());
                    }),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
            child: OutlinedButton(
                onPressed: _loading ? null : _load, child: const Text('重新检测'))),
        const SizedBox(width: 12),
        Expanded(
            child: FilledButton(
                onPressed: _loading ||
                        _adapter == null ||
                        helper == null ||
                        wake.error != null
                    ? null
                    : () {
                        _agentId = helper.id;
                        _go(1);
                      },
                child: const Text('下一步')))
      ]),
    ];
  }

  List<Widget> _bios() => [
        _panel([
          const Text('开启主板网络唤醒',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Text('BIOS 设置需要你在电脑上完成，应用无法自动检测或修改。'),
          const SizedBox(height: 20),
          const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text('1')),
              title: Text('进入 BIOS'),
              subtitle: Text('保存当前工作，重启电脑。开机时按主板说明进入 BIOS，常见按键为 Del 或 F2。')),
          const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text('2')),
              title: Text('开启网络唤醒'),
              subtitle: Text(
                  '在电源管理中查找 Wake on LAN 或 PCIe 唤醒并启用。若 ErP 会切断网卡待机供电，按主板说明关闭它。')),
          const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text('3')),
              title: Text('保存并返回'),
              subtitle: Text('保存 BIOS 设置后启动 Windows，再回到这里继续。不同主板的名称和位置可能不同。')),
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _biosConfirmed,
              onChanged: (v) => setState(() {
                    _biosConfirmed = v ?? false;
                  }),
              title: const Text('已核对 BIOS 设置，电脑保持接通电源')),
        ]),
        Row(children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: () => _go(0), child: const Text('上一步'))),
          const SizedBox(width: 12),
          Expanded(
              child: FilledButton(
                  onPressed: _biosConfirmed ? () => _go(2) : null,
                  child: const Text('下一步')))
        ]),
      ];
  List<Widget> _test(WakeProvider wake) => [
        _panel([
          Text(_saved ? '配置已保存，接下来测试开机' : '保存并开始测试',
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(_saved
              ? '配置成功不等于硬件已通过唤醒测试。请按下面的顺序验证。'
              : '保存后，同一账号的手机和电脑都能看到这台电脑。'),
          if (!_saved) ...[
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _sameNetwork,
                onChanged: (v) => setState(() {
                      _sameNetwork = v ?? false;
                    }),
                title: const Text('家中安卓助手与电脑连接同一路由器')),
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _startup,
                onChanged: (v) => setState(() {
                      _startup = v ?? false;
                    }),
                title: const Text('登录 Windows 后自动启动 RDesk'),
                subtitle: const Text('用于确认电脑上线；不会跳过 Windows 登录。')),
            if (_check?.allEnabled != true)
              _notice('检测中仍有未开启或无法判断的项目，请先核对网卡属性。保存配置不会自动修改这些设置。'),
          ],
          const SizedBox(height: 12),
          const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.bedtime_outlined),
              title: Text('先测试睡眠唤醒'),
              subtitle: Text('让电脑进入睡眠，在另一台设备的 RDesk 中点击“开机”。')),
          const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.power_settings_new),
              title: Text('再测试关机与外网'),
              subtitle: Text('睡眠测试成功后再测试关机。在另一台手机使用移动网络发起开机；家中助手始终保持 Wi-Fi。')),
          const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.nights_stay_outlined),
              title: Text('最后测试隔夜'),
              subtitle: Text('让家中助手锁屏并保持供电，隔夜再次尝试。“信号已发送”不等于电脑已启动。')),
          const Text('Windows 关机唤醒受硬件、驱动和快速启动影响；当前 Windows 客户端不提供被控桌面功能。',
              style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
        ]),
        if (_saved)
          FilledButton(
              onPressed: () => context.pop(), child: const Text('返回电脑列表'))
        else
          Row(children: [
            Expanded(
                child: OutlinedButton(
                    onPressed: _saving ? null : () => _go(1),
                    child: const Text('上一步'))),
            const SizedBox(width: 12),
            Expanded(
                child: FilledButton(
                    onPressed: _saving || !_sameNetwork || wake.busy
                        ? null
                        : () => _save(wake),
                    child: Text(_saving ? '正在保存…' : '保存配置')))
          ]),
      ];
  Future<void> _save(WakeProvider wake) async {
    final helper = _selectedAgent(wake);
    if (helper == null || _adapter == null || _name.text.trim().isEmpty) {
      setState(() {
        _error = '请返回检测步骤，确认电脑名称、网卡与在线助手。';
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final local = await RdeskBridgeService.instance.getLocalDeviceInfo();
      if (!mounted) return;
      await wake.windows!.setLoginStartup(_startup);
      if (!mounted) return;
      final ok = await wake.enrollWindows(
          deviceId: local.deviceId,
          name: _name.text.trim(),
          mac: _adapter!.mac,
          agentId: helper.id);
      if (mounted && ok) {
        setState(() {
          _saved = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '保存失败，请检查登录状态和启动设置后重试。';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  List<Widget> _helper(WakeProvider wake) => [
        _panel([
          const Icon(Icons.phonelink_ring, size: 56, color: Color(0xff3979ff)),
          const SizedBox(height: 16),
          const Text('把这台手机留在家中',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text('连接电脑所在的家庭 Wi-Fi，并持续供电。无需开启屏幕共享。'),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('家中开机助手'),
              subtitle: Text(wake.helper.enabled
                  ? '已启动，可在通知栏停止'
                  : '开启后可被同账号的 Windows 电脑发现'),
              value: wake.helper.enabled,
              onChanged: wake.busy
                  ? null
                  : (v) async {
                      if (v) {
                        await wake.enableHelper(_name.text.trim());
                      } else {
                        await wake.disableHelper();
                      }
                    }),
          if (wake.helper.enabled)
            _status('家庭 Wi-Fi', wake.helper.networkReady ? '通道可用' : '通道未就绪',
                ok: wake.helper.networkReady),
          if (wake.helper.errorCode != null)
            _notice('助手状态：${wake.helper.errorCode}', error: true),
          TextButton(
              onPressed: wake.agent.openBatterySettings,
              child: const Text('允许后台运行')),
          const Text('在系统中将电池策略设为不限制，并允许自启动。切换 Wi-Fi、手机重启或强制停止后，请重新打开并启用助手。'),
        ]),
        _panel([
          const Text('接下来，到 Windows 电脑上继续',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('登录同一账号，进入“远程开机”，点击“启用远程开机”。配置后可在外出的其他手机或电脑上发起开机。'),
        ]),
        ExpansionTile(title: const Text('名称与助手管理'), children: [
          TextField(
              controller: _name,
              maxLength: 40,
              decoration: const InputDecoration(labelText: '助手名称（下次启用时生效）')),
          for (final a in wake.agents)
            ListTile(
                title: Text(a.name),
                subtitle: Text(a.online ? '在线' : '离线'),
                trailing: IconButton(
                    tooltip: '删除助手',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: wake.busy
                        ? null
                        : () async {
                            final yes = await showDialog<bool>(
                                context: context,
                                builder: (dialog) => AlertDialog(
                                        title: const Text('删除助手？'),
                                        content:
                                            const Text('绑定此助手的电脑需要重新选择助手。'),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(dialog, false),
                                              child: const Text('取消')),
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(dialog, true),
                                              child: const Text('删除'))
                                        ]));
                            if (yes == true) await wake.removeHelper(a);
                          })),
        ]),
      ];
}
