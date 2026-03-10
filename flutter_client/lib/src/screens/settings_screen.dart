import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/android_host_provider.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        automaticallyImplyLeading: false,
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('安全', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.lock),
                      title: const Text('永久密码'),
                      subtitle: Text(
                          settings.permanentPassword != null ? '已设置' : '未设置'),
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
                    SwitchListTile(
                      secondary: const Icon(Icons.content_paste_go),
                      title: const Text('自动同步剪贴板'),
                      subtitle: const Text('远控会话中自动双向同步文本剪贴板'),
                      value: settings.autoClipboardSync,
                      onChanged: settings.setAutoClipboardSync,
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.verified_user_outlined),
                      title: const Text('记住受信设备'),
                      subtitle: const Text('保存最近成功连接的设备密码，用于快捷重连'),
                      value: settings.rememberTrustedPeers,
                      onChanged: settings.setRememberTrustedPeers,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('受信设备', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: settings.trustedPeers.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('暂无受信设备。成功连接后会自动加入这里。'),
                      )
                    : Column(
                        children: [
                          for (final peer in settings.trustedPeers)
                            ListTile(
                              leading: const Icon(Icons.devices_other),
                              title:
                                  Text('${peer.hostname} (${peer.deviceId})'),
                              subtitle: Text(
                                '${peer.peerOs} · 最近使用 ${peer.lastUsedAt.toString().substring(0, 16)}',
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: '移除',
                                onPressed: () =>
                                    settings.removeTrustedPeer(peer.deviceId),
                              ),
                            ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.delete_sweep_outlined),
                            title: const Text('清空受信设备'),
                            subtitle: const Text('移除所有本地缓存的设备密码'),
                            onTap: settings.clearTrustedPeers,
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 24),
              Text('受信查看端', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: settings.trustedIncomingViewers.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('暂无受信查看端。首次成功连接后会自动加入这里。'),
                      )
                    : Column(
                        children: [
                          for (final viewer in settings.trustedIncomingViewers)
                            ListTile(
                              leading: const Icon(Icons.verified_user_outlined),
                              title: Text(
                                  '${viewer.hostname} (${viewer.deviceId})'),
                              subtitle: Text(
                                '${viewer.peerOs} · 最近通过 ${viewer.lastUsedAt.toString().substring(0, 16)}',
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: '移除',
                                onPressed: () =>
                                    settings.removeTrustedIncomingViewer(
                                        viewer.deviceId),
                              ),
                            ),
                          const Divider(height: 1),
                          ListTile(
                            leading:
                                const Icon(Icons.person_remove_alt_1_outlined),
                            title: const Text('清空受信查看端'),
                            subtitle: const Text('关闭密码免输的自动接受列表'),
                            onTap: settings.clearTrustedIncomingViewers,
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 24),
              Text('网络', style: Theme.of(context).textTheme.titleMedium),
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
              Text('外观', style: Theme.of(context).textTheme.titleMedium),
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
              if (!kIsWeb &&
                  defaultTargetPlatform == TargetPlatform.android) ...[
                const SizedBox(height: 24),
                Text('安卓被控端', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Consumer<AndroidHostProvider>(
                  builder: (context, host, _) {
                    final stateText = switch (host.state.state) {
                      'ready' => '已授权，待启动推流',
                      'running' => '前台服务运行中',
                      'requesting' => '等待授权',
                      'error' => '状态异常',
                      _ => '未授权',
                    };
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  host.state.isRunning
                                      ? Icons.cast_connected
                                      : host.state.hasPermission
                                          ? Icons.verified_user
                                          : Icons.screenshot_monitor,
                                  color: host.state.isRunning
                                      ? Colors.green
                                      : Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '屏幕共享准备状态',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$stateText · ${host.state.accessibilityEnabled ? "已启用无障碍控制" : "未启用无障碍控制"}',
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: host.busy ? null : host.refresh,
                                  icon: const Icon(Icons.refresh),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              '先授予录屏权限，再启动前台服务。若要让远程点击真正落到系统界面，请额外开启 RDesk 无障碍控制服务。',
                            ),
                            if (host.error != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                host.error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                            if (host.lanRelayEndpoint != null) ...[
                              const SizedBox(height: 12),
                              SelectableText(
                                '局域网预览地址：${host.lanRelayEndpoint}/frame.jpg',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                '把 Android 和 Mac 两端的“信令服务器”都设置成运行中的 rdesk_server 地址。当前地址用于注册真实采集帧，Mac 会按设备ID查到这一路预览流。',
                              ),
                            ],
                            if (host.lastRemoteTap != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                '最近一次远程点击：${host.lastRemoteTap}',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (host.lastRemoteAction != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                '最近一次远程动作：${host.lastRemoteAction}',
                                style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.secondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (host.lastRemoteGesture != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                '最近一次远程手势：${host.lastRemoteGesture}',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.tertiary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (host.lastRemoteText != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                '最近一次远程文本：${host.lastRemoteText}',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (host.lastRemoteClipboard != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                '最近一次远程剪贴板：${host.lastRemoteClipboard}',
                                style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.secondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            if (host.previewFrame != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: AspectRatio(
                                  aspectRatio: host.previewFrame!.width > 0 &&
                                          host.previewFrame!.height > 0
                                      ? host.previewFrame!.width /
                                          host.previewFrame!.height
                                      : 16 / 9,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.memory(
                                        host.previewFrame!.bytes,
                                        fit: BoxFit.cover,
                                        gaplessPlayback: true,
                                      ),
                                      Positioned(
                                        left: 12,
                                        top: 12,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black
                                                .withValues(alpha: 0.55),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: const Text(
                                            '实时采集预览',
                                            style:
                                                TextStyle(color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                FilledButton.icon(
                                  onPressed:
                                      host.busy ? null : host.requestPermission,
                                  icon: const Icon(Icons.security),
                                  label: const Text('申请录屏权限'),
                                ),
                                OutlinedButton.icon(
                                  onPressed:
                                      host.busy || !host.state.hasPermission
                                          ? null
                                          : host.startHosting,
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('启动服务'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: host.busy || !host.state.isRunning
                                      ? null
                                      : host.stopHosting,
                                  icon: const Icon(Icons.stop),
                                  label: const Text('停止服务'),
                                ),
                                FilledButton.tonalIcon(
                                  onPressed: host.busy || !host.canDisconnectViewers
                                      ? null
                                      : () async {
                                          final ok = await host.disconnectCurrentViewer();
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(ok ? '已断开当前远控连接' : '断开远控失败'),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        },
                                  icon: const Icon(Icons.link_off),
                                  label: const Text('断开当前远控'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: host.openAccessibilitySettings,
                                  icon: const Icon(Icons.accessibility_new),
                                  label: const Text('开启无障碍控制'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
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

  void _showPasswordDialog(BuildContext context, SettingsProvider settings) {
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
