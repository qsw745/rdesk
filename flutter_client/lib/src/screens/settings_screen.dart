import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('安全',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.lock),
                      title: const Text('永久密码'),
                      subtitle: Text(settings.permanentPassword != null
                          ? '已设置'
                          : '未设置'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showPasswordDialog(context, settings),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.check_circle),
                      title: const Text('自动接受连接'),
                      subtitle: const Text('自动处理来自受信设备的连接请求'),
                      value: settings.autoAccept,
                      onChanged: settings.setAutoAccept,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Text('网络',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.dns),
                      title: const Text('信令服务器'),
                      subtitle: Text(settings.signalingServer),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showServerDialog(
                        context,
                        '信令服务器',
                        settings.signalingServer,
                        settings.updateSignalingServer,
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.swap_horiz),
                      title: const Text('中继服务器'),
                      subtitle: Text(settings.relayServer),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showServerDialog(
                        context,
                        '中继服务器',
                        settings.relayServer,
                        settings.updateRelayServer,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              Text('外观',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('跟随系统'),
                        selected: settings.theme == 'system',
                        onSelected: (_) => settings.setTheme('system'),
                      ),
                      ChoiceChip(
                        label: const Text('浅色'),
                        selected: settings.theme == 'light',
                        onSelected: (_) => settings.setTheme('light'),
                      ),
                      ChoiceChip(
                        label: const Text('深色'),
                        selected: settings.theme == 'dark',
                        onSelected: (_) => settings.setTheme('dark'),
                      ),
                    ],
                  ),
                ),
              ),

              Text('关于', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.info),
                      title: Text('版本'),
                      subtitle: Text('0.1.0'),
                    ),
                    ListTile(
                      leading: Icon(Icons.code),
                      title: Text('RDesk 项目'),
                      subtitle: Text('跨平台远程控制软件原型'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showPasswordDialog(
      BuildContext context, SettingsProvider settings) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置永久密码'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '密码',
            hintText: '留空表示清除',
          ),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final pwd = controller.text.trim();
              settings.setPermanentPassword(pwd.isEmpty ? null : pwd);
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showServerDialog(
    BuildContext context,
    String title,
    String currentValue,
    Future<void> Function(String) onSave,
  ) {
    final controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '服务器地址',
            hintText: 'host:port',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              onSave(controller.text.trim());
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
