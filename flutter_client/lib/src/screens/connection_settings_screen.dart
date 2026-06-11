import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';

class ConnectionSettingsScreen extends StatelessWidget {
  const ConnectionSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('连接设置')),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _SectionCard(
                title: '网络',
                children: [
                  _SettingTile(
                    icon: Icons.dns_rounded,
                    title: '信令服务器',
                    subtitle: settings.signalingServer,
                    onTap: () => _showServerEditDialog(
                      context,
                      title: '信令服务器',
                      initialValue: settings.signalingServer,
                      onSubmit: settings.updateSignalingServer,
                    ),
                  ),
                  _SettingTile(
                    icon: Icons.swap_horiz_rounded,
                    title: '中继服务器',
                    subtitle: settings.relayServer,
                    onTap: () => _showServerEditDialog(
                      context,
                      title: '中继服务器',
                      initialValue: settings.relayServer,
                      onSubmit: settings.updateRelayServer,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: '连接行为',
                children: [
                  SwitchListTile.adaptive(
                    value: settings.autoAccept,
                    onChanged: settings.setAutoAccept,
                    title: const Text('自动接受免密连接'),
                    subtitle: const Text('受信设备发起请求时自动通过'),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  ),
                  SwitchListTile.adaptive(
                    value: settings.autoClipboardSync,
                    onChanged: settings.setAutoClipboardSync,
                    title: const Text('自动同步剪贴板'),
                    subtitle: const Text('会话中自动同步本地和远端剪贴板'),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showServerEditDialog(
    BuildContext context, {
    required String title,
    required String initialValue,
    required Future<void> Function(String) onSubmit,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text('修改$title'),
              content: Form(
                key: formKey,
                child: TextFormField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '例如 qisw.top:80',
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) {
                      return '地址不能为空';
                    }
                    return null;
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() ?? false) {
                      Navigator.of(dialogContext).pop(true);
                    }
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    final value = controller.text.trim();
    if (value.isEmpty) {
      return;
    }
    await onSubmit(value);
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
