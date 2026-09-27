import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../providers/wake_provider.dart';
import '../services/desktop_wake_agent.dart';
import '../services/login_item_service.dart';
import '../services/wake_agent_channel.dart';

class MacWakeHelperPanel extends StatefulWidget {
  final WakeProvider wake;
  final LoginItemService loginItem;
  const MacWakeHelperPanel(
      {super.key,
      required this.wake,
      this.loginItem = const LoginItemService()});
  @override
  State<MacWakeHelperPanel> createState() => _MacWakeHelperPanelState();
}

class _MacWakeHelperPanelState extends State<MacWakeHelperPanel> {
  bool _loading = false;
  String? _error;
  LoginItemState _login = const LoginItemState();

  @override
  void initState() {
    super.initState();
    _loadLoginItem();
  }

  Future<void> _loadLoginItem() async {
    try {
      final state = await widget.loginItem.status();
      if (mounted) setState(() => _login = state);
    } on PlatformException catch (e) {
      debugPrint('[RDesk] login item status failed: ${e.code}');
    }
  }

  Future<void> _setLoginItem(bool enabled) async {
    try {
      final state = await widget.loginItem.set(enabled);
      if (mounted) setState(() => _login = state);
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? '无法更改登录项');
    }
  }

  Future<void> _enable() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final wake = widget.wake;
    final gen = wake.identityGeneration;
    try {
      final networks = await wake.agent.desktop.networks();
      if (!mounted || gen != wake.identityGeneration) return;
      if (networks.isEmpty) throw StateError('未找到家庭局域网，请连接电脑所在的 Wi-Fi 或网线');
      final selected = await showDialog<DesktopWakeNetwork>(
          context: context,
          builder: (dialog) =>
              SimpleDialog(title: const Text('选择电脑所在的家庭网络'), children: [
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('请选择主家庭网络，不能使用访客网络、VPN 或手机热点。')),
                for (final network in networks)
                  SimpleDialogOption(
                      onPressed: () => Navigator.pop(dialog, network),
                      child: Text('${network.name} · ${network.cidr}')),
              ]));
      if (!mounted || selected == null || gen != wake.identityGeneration) {
        return;
      }
      wake.agent.desktop.selected = selected;
      await wake.enableHelper('家中 Mac');
    } catch (e) {
      if (mounted && gen == wake.identityGeneration) {
        setState(() {
          _error = e is StateError ? e.message : '助手准备失败，请重新尝试';
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
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('用这台 Mac 代发开机信号'),
                subtitle: Text(widget.wake.helper.enabled
                    ? '助手已启动 · 请留在家庭网络并保持 Mac 唤醒'
                    : '无需安卓手机，适合先测试外网开机'),
                value: widget.wake.helper.enabled,
                onChanged: _loading || widget.wake.busy
                    ? null
                    : (v) async {
                        if (v) {
                          await _enable();
                        } else {
                          await widget.wake.disableHelper();
                        }
                      }),
            if (_login.supported)
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('登录 Mac 后自动打开 RDesk'),
                  subtitle: Text(_login.requiresApproval
                      ? '需要在系统设置的「登录项」中允许 RDesk'
                      : 'Mac 重启或更新后，助手可在同一家庭网络自动恢复'),
                  value: _login.enabled || _login.requiresApproval,
                  onChanged: (v) => _setLoginItem(v)),
            if (_login.requiresApproval)
              Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                      onPressed: widget.loginItem.openSettings,
                      child: const Text('打开登录项设置'))),
            const Text(
                '此 Mac 必须与 Windows 连接同一路由器，保持供电、系统唤醒且 RDesk 运行。锁屏可继续运行；合盖睡眠时无法代发。Wi-Fi 短暂断开或路由器重启后，回到同一网络会自动继续；重新打开 RDesk 时，只在同一家庭网络自动恢复助手。不会修改你的电源设置。'),
            if (widget.wake.helper.errorCode != null)
              Text(describeHelperError(widget.wake.helper.errorCode!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ])));
}
