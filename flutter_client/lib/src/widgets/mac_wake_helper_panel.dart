import 'package:flutter/material.dart';
import '../providers/wake_provider.dart';
import '../services/desktop_wake_agent.dart';

class MacWakeHelperPanel extends StatefulWidget {
  final WakeProvider wake;
  const MacWakeHelperPanel({super.key, required this.wake});
  @override
  State<MacWakeHelperPanel> createState() => _MacWakeHelperPanelState();
}

class _MacWakeHelperPanelState extends State<MacWakeHelperPanel> {
  bool _loading = false;
  String? _error;
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
      if (!mounted || selected == null || gen != wake.identityGeneration)
        return;
      wake.agent.desktop.selected = selected;
      await wake.enableHelper('家中 Mac');
    } catch (e) {
      if (mounted && gen == wake.identityGeneration)
        setState(() {
          _error = e is StateError ? e.message : '助手准备失败，请重新尝试';
        });
    } finally {
      if (mounted)
        setState(() {
          _loading = false;
        });
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
            const Text(
                '此 Mac 必须与 Windows 连接同一路由器，保持供电、系统唤醒且 RDesk 运行。锁屏可继续运行；合盖睡眠、退出 App 或重启后需要重新检查并启用。不会自动修改你的电源设置。'),
            if (widget.wake.helper.errorCode != null)
              Text(widget.wake.helper.errorCode!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ])));
}
