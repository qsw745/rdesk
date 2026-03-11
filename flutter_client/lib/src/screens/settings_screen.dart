import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/android_host_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        automaticallyImplyLeading: false,
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _SettingsOverviewCard(
                autoAccept: settings.autoAccept,
                trustedPeerCount: settings.trustedPeers.length,
                trustedViewerCount: settings.trustedIncomingViewers.length,
              ),
              const SizedBox(height: 24),
              // ── 安全 ──
              _SectionHeader(icon: Icons.shield_outlined, label: '安全'),
              const SizedBox(height: 10),
              _CardContainer(
                isDark: isDark,
                child: Column(
                  children: [
                    ListTile(
                      leading: _SettingIcon(
                        icon: Icons.lock_outline,
                        color: AppTheme.primaryBlue,
                      ),
                      title: const Text('永久密码'),
                      subtitle: Text(
                        settings.permanentPassword != null ? '已设置' : '未设置',
                        style: TextStyle(
                          color: settings.permanentPassword != null
                              ? AppTheme.successGreen
                              : Colors.grey.shade500,
                          fontSize: 13,
                        ),
                      ),
                      trailing:
                          const Icon(Icons.chevron_right_rounded, size: 20),
                      onTap: () => _showPasswordDialog(context, settings),
                    ),
                    _divider(isDark),
                    _SwitchTile(
                      icon: Icons.check_circle_outline,
                      iconColor: AppTheme.successGreen,
                      title: '自动接受连接',
                      subtitle: '自动处理来自受信设备的连接请求',
                      value: settings.autoAccept,
                      onChanged: settings.setAutoAccept,
                    ),
                    _divider(isDark),
                    _SwitchTile(
                      icon: Icons.content_paste_go_rounded,
                      iconColor: AppTheme.accentPurple,
                      title: '自动同步剪贴板',
                      subtitle: '远控会话中自动双向同步文本剪贴板',
                      value: settings.autoClipboardSync,
                      onChanged: settings.setAutoClipboardSync,
                    ),
                    _divider(isDark),
                    _SwitchTile(
                      icon: Icons.verified_user_outlined,
                      iconColor: AppTheme.warningAmber,
                      title: '记住受信设备',
                      subtitle: '保存最近成功连接的设备密码，用于快捷重连',
                      value: settings.rememberTrustedPeers,
                      onChanged: settings.setRememberTrustedPeers,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              _SectionHeader(icon: Icons.devices_other_rounded, label: '受信设备'),
              const SizedBox(height: 10),
              _CardContainer(
                isDark: isDark,
                child: settings.trustedPeers.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 24, horizontal: 16),
                        child: Column(
                          children: [
                            Icon(Icons.device_unknown_rounded,
                                size: 32, color: Colors.grey.shade400),
                            const SizedBox(height: 10),
                            Text(
                              '暂无受信设备',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '成功连接后会自动加入这里',
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          for (var i = 0;
                              i < settings.trustedPeers.length;
                              i++) ...[
                            if (i > 0) _divider(isDark),
                            ListTile(
                              leading: _SettingIcon(
                                icon: Icons.devices_rounded,
                                color: AppTheme.primaryBlue,
                              ),
                              title: Text(
                                '${settings.trustedPeers[i].hostname}',
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w500),
                              ),
                              subtitle: Text(
                                '${settings.trustedPeers[i].peerOs} · ${settings.trustedPeers[i].lastUsedAt.toString().substring(0, 16)}',
                                style: TextStyle(
                                    color: Colors.grey.shade500, fontSize: 12),
                              ),
                              trailing: IconButton(
                                icon: Icon(Icons.delete_outline_rounded,
                                    size: 20,
                                    color: AppTheme.errorRed
                                        .withValues(alpha: 0.7)),
                                onPressed: () => settings.removeTrustedPeer(
                                    settings.trustedPeers[i].deviceId),
                              ),
                            ),
                          ],
                          _divider(isDark),
                          ListTile(
                            leading: _SettingIcon(
                              icon: Icons.delete_sweep_outlined,
                              color: AppTheme.errorRed,
                            ),
                            title: const Text('清空受信设备',
                                style: TextStyle(fontSize: 14)),
                            subtitle: Text('移除所有本地缓存的设备密码',
                                style: TextStyle(
                                    color: Colors.grey.shade500, fontSize: 12)),
                            onTap: settings.clearTrustedPeers,
                          ),
                        ],
                      ),
              ),

              const SizedBox(height: 24),
              _SectionHeader(icon: Icons.visibility_outlined, label: '受信查看端'),
              const SizedBox(height: 10),
              _CardContainer(
                isDark: isDark,
                child: settings.trustedIncomingViewers.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 24, horizontal: 16),
                        child: Column(
                          children: [
                            Icon(Icons.person_search_rounded,
                                size: 32, color: Colors.grey.shade400),
                            const SizedBox(height: 10),
                            Text(
                              '暂无受信查看端',
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '首次成功连接后会自动加入',
                              style: TextStyle(
                                  color: Colors.grey.shade400, fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          for (var i = 0;
                              i < settings.trustedIncomingViewers.length;
                              i++) ...[
                            if (i > 0) _divider(isDark),
                            ListTile(
                              leading: _SettingIcon(
                                icon: Icons.verified_user_outlined,
                                color: AppTheme.successGreen,
                              ),
                              title: Text(
                                '${settings.trustedIncomingViewers[i].hostname}',
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w500),
                              ),
                              subtitle: Text(
                                '${settings.trustedIncomingViewers[i].peerOs} · ${settings.trustedIncomingViewers[i].lastUsedAt.toString().substring(0, 16)}',
                                style: TextStyle(
                                    color: Colors.grey.shade500, fontSize: 12),
                              ),
                              trailing: IconButton(
                                icon: Icon(Icons.delete_outline_rounded,
                                    size: 20,
                                    color: AppTheme.errorRed
                                        .withValues(alpha: 0.7)),
                                onPressed: () => settings
                                    .removeTrustedIncomingViewer(settings
                                        .trustedIncomingViewers[i].deviceId),
                              ),
                            ),
                          ],
                          _divider(isDark),
                          ListTile(
                            leading: _SettingIcon(
                              icon: Icons.person_remove_alt_1_outlined,
                              color: AppTheme.errorRed,
                            ),
                            title: const Text('清空受信查看端',
                                style: TextStyle(fontSize: 14)),
                            subtitle: Text('关闭密码免输的自动接受列表',
                                style: TextStyle(
                                    color: Colors.grey.shade500, fontSize: 12)),
                            onTap: settings.clearTrustedIncomingViewers,
                          ),
                        ],
                      ),
              ),

              const SizedBox(height: 24),
              _SectionHeader(icon: Icons.language_rounded, label: '网络'),
              const SizedBox(height: 10),
              _CardContainer(
                isDark: isDark,
                child: Column(
                  children: [
                    ListTile(
                      leading: _SettingIcon(
                        icon: Icons.dns_outlined,
                        color: AppTheme.primaryBlue,
                      ),
                      title:
                          const Text('信令服务器', style: TextStyle(fontSize: 14)),
                      subtitle: Text(settings.signalingServer,
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 12)),
                      trailing:
                          const Icon(Icons.chevron_right_rounded, size: 20),
                      onTap: () => _showServerDialog(
                        context,
                        '信令服务器',
                        settings.signalingServer,
                        settings.updateSignalingServer,
                      ),
                    ),
                    _divider(isDark),
                    ListTile(
                      leading: _SettingIcon(
                        icon: Icons.swap_horiz_rounded,
                        color: AppTheme.accentPurple,
                      ),
                      title:
                          const Text('中继服务器', style: TextStyle(fontSize: 14)),
                      subtitle: Text(settings.relayServer,
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 12)),
                      trailing:
                          const Icon(Icons.chevron_right_rounded, size: 20),
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
              _SectionHeader(icon: Icons.palette_outlined, label: '外观'),
              const SizedBox(height: 10),
              _CardContainer(
                isDark: isDark,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _ThemeOption(
                        label: '跟随系统',
                        icon: Icons.brightness_auto_outlined,
                        selected: settings.theme == 'system',
                        onTap: () => settings.setTheme('system'),
                        isDark: isDark,
                      ),
                      const SizedBox(width: 10),
                      _ThemeOption(
                        label: '浅色',
                        icon: Icons.light_mode_outlined,
                        selected: settings.theme == 'light',
                        onTap: () => settings.setTheme('light'),
                        isDark: isDark,
                      ),
                      const SizedBox(width: 10),
                      _ThemeOption(
                        label: '深色',
                        icon: Icons.dark_mode_outlined,
                        selected: settings.theme == 'dark',
                        onTap: () => settings.setTheme('dark'),
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),
              ),

              // Android host section
              if (!kIsWeb &&
                  defaultTargetPlatform == TargetPlatform.android) ...[
                const SizedBox(height: 24),
                _SectionHeader(
                    icon: Icons.cast_connected_rounded, label: '安卓被控端'),
                const SizedBox(height: 10),
                Consumer<AndroidHostProvider>(
                  builder: (context, host, _) {
                    return _AndroidHostCard(
                      host: host,
                      isDark: isDark,
                      onDisconnect: () =>
                          _confirmDisconnectViewers(context, host),
                    );
                  },
                ),
              ],

              const SizedBox(height: 24),
              _SectionHeader(icon: Icons.info_outline_rounded, label: '关于'),
              const SizedBox(height: 10),
              _CardContainer(
                isDark: isDark,
                child: Column(
                  children: [
                    ListTile(
                      leading: _SettingIcon(
                        icon: Icons.tag_rounded,
                        color: Colors.grey,
                      ),
                      title: const Text('版本', style: TextStyle(fontSize: 14)),
                      subtitle: Text('0.1.0',
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 12)),
                    ),
                    _divider(isDark),
                    ListTile(
                      leading: _SettingIcon(
                        icon: Icons.code_rounded,
                        color: Colors.grey,
                      ),
                      title: const Text('RDesk 项目',
                          style: TextStyle(fontSize: 14)),
                      subtitle: Text('跨平台远程控制软件原型',
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 12)),
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

  void _confirmDisconnectViewers(
      BuildContext context, AndroidHostProvider host) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('断开远控连接'),
        content: const Text('确定要断开当前所有远程查看端的连接吗？\n断开后对方需要重新输入密码才能连接。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await host.disconnectCurrentViewer();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok ? '已断开所有远控连接并刷新密钥' : '断开操作部分完成，请检查连接状态'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
            child: const Text('确认断开'),
          ),
        ],
      ),
    );
  }

  void _showPasswordDialog(BuildContext context, SettingsProvider settings) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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

  static Widget _divider(bool isDark) => Divider(
        height: 1,
        indent: 60,
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.grey.shade100,
      );
}

class _SettingsOverviewCard extends StatelessWidget {
  final bool autoAccept;
  final int trustedPeerCount;
  final int trustedViewerCount;

  const _SettingsOverviewCard({
    required this.autoAccept,
    required this.trustedPeerCount,
    required this.trustedViewerCount,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF1C2440), Color(0xFF151B2D)]
              : const [Color(0xFFF7FAFF), Color(0xFFEFF4FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : AppTheme.primaryBlue.withValues(alpha: 0.10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前安全概览',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            autoAccept ? '已对受信查看端开启自动接受。' : '当前仍需手动确认新的远控连接。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.white70 : AppTheme.textMuted,
                ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _OverviewMetric(
                  icon: Icons.devices_other_rounded,
                  label: '受信设备',
                  value: '$trustedPeerCount',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _OverviewMetric(
                  icon: Icons.visibility_rounded,
                  label: '受信查看端',
                  value: '$trustedViewerCount',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _OverviewMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryBlue),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.white70 : AppTheme.textMuted,
                ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primaryBlue),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

class _CardContainer extends StatelessWidget {
  final bool isDark;
  final Widget child;

  const _CardContainer({required this.isDark, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.04),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _SettingIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _SettingIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: _SettingIcon(icon: icon, color: iconColor),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(subtitle,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;

  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primaryBlue.withValues(alpha: 0.1)
                : isDark
                    ? const Color(0xFF2A2A3C)
                    : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? AppTheme.primaryBlue.withValues(alpha: 0.3)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? AppTheme.primaryBlue : Colors.grey.shade500,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? AppTheme.primaryBlue : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AndroidHostCard extends StatelessWidget {
  final AndroidHostProvider host;
  final bool isDark;
  final VoidCallback onDisconnect;

  const _AndroidHostCard({
    required this.host,
    required this.isDark,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final stateText = switch (host.state.state) {
      'ready' => host.guardModeEnabled ? '守护模式待命中' : '已授权，待启动推流',
      'running' => host.guardModeEnabled ? '守护模式运行中' : '前台服务运行中',
      'requesting' => '等待录屏授权',
      'error' => '状态异常',
      _ => '未完成初始化',
    };

    final stateColor = host.state.isRunning
        ? AppTheme.successGreen
        : host.state.hasPermission
            ? AppTheme.warningAmber
            : Colors.grey;

    return _CardContainer(
      isDark: isDark,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: stateColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    host.state.isRunning
                        ? Icons.cast_connected_rounded
                        : host.state.hasPermission
                            ? Icons.verified_user_outlined
                            : Icons.screenshot_monitor_rounded,
                    color: stateColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '安卓守护模式',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: stateColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '$stateText · ${host.state.accessibilityEnabled ? "无障碍已开启" : "无障碍未开启"}',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade500),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: host.busy ? null : host.refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
              ],
            ),

            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: host.guardModeEnabled,
                    onChanged: host.busy ? null : host.setGuardModeEnabled,
                    title: const Text('保持安卓随时待控'),
                    subtitle: Text(
                      host.guardModeEnabled
                          ? '已启用：进入 App 时会尽量自动恢复前台服务并保持在线。'
                          : '关闭后将只保留手动启动的被控端服务。',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '一次性完成下面清单后，iPhone 端发起远控会更顺畅；但 Android 录屏授权在重启、系统回收或权限失效后，仍可能需要你再确认一次。',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _ChecklistTile(
              label: '录屏权限',
              description: host.state.hasPermission
                  ? '已授予；守护模式可直接恢复前台服务。'
                  : '首次必须手动确认系统录屏弹窗。',
              done: host.state.hasPermission,
              actionLabel: '去授权',
              onPressed: host.busy ? null : host.requestPermission,
            ),
            const SizedBox(height: 10),
            _ChecklistTile(
              label: '无障碍控制',
              description: host.state.accessibilityEnabled
                  ? '已开启；远程点击、返回、拖拽、文本输入可下发到系统界面。'
                  : '未开启时只能看屏幕，无法稳定控制系统 UI。',
              done: host.state.accessibilityEnabled,
              actionLabel: '去开启',
              onPressed: host.openAccessibilitySettings,
            ),
            const SizedBox(height: 10),
            _ChecklistTile(
              label: '悬浮窗 / Overlay',
              description: host.state.overlayEnabled
                  ? '已允许；便于后续扩展远控提示与状态浮层。'
                  : '建议开启，避免后续提示被系统拦截。',
              done: host.state.overlayEnabled,
              actionLabel: '去设置',
              onPressed: host.openOverlaySettings,
            ),
            const SizedBox(height: 10),
            _ChecklistTile(
              label: '通知权限',
              description: host.state.notificationsEnabled
                  ? '已允许；前台服务通知更稳定。'
                  : '建议开启，否则系统可能限制前台服务可见性。',
              done: host.state.notificationsEnabled,
              actionLabel: '去设置',
              onPressed: host.openNotificationSettings,
            ),
            const SizedBox(height: 10),
            _ChecklistTile(
              label: '忽略电池优化',
              description: host.state.batteryOptimizationIgnored
                  ? '已加入白名单；后台驻留更稳定。'
                  : '建议改为不受限制，减少系统杀后台。',
              done: host.state.batteryOptimizationIgnored,
              actionLabel: '去设置',
              onPressed: host.openBatteryOptimizationSettings,
            ),
            const SizedBox(height: 10),
            _ChecklistTile(
              label: '厂商自启动 / 后台保护',
              description: host.autostartGuidance,
              done: false,
              actionLabel: '应用详情',
              onPressed: host.openAppDetailsSettings,
            ),

            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (host.isReadyForRemoteRequests
                        ? AppTheme.successGreen
                        : AppTheme.warningAmber)
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    host.isReadyForRemoteRequests
                        ? Icons.verified_rounded
                        : Icons.info_outline_rounded,
                    size: 18,
                    color: host.isReadyForRemoteRequests
                        ? AppTheme.successGreen
                        : AppTheme.warningAmber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      host.isReadyForRemoteRequests
                          ? '主要守护项已就绪。只要录屏权限没有被系统回收，Android 会尽量保持在线并等待 iPhone 发起连接。'
                          : '还有初始化项未完成。即使已能看屏幕，也建议把清单补齐，才能降低下次远控失败或被系统回收的概率。',
                      style: const TextStyle(fontSize: 12.5, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),

            if (host.error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.errorRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.errorRed.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppTheme.errorRed, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        host.error!,
                        style: const TextStyle(
                            color: AppTheme.errorRed, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (host.lanRelayEndpoint != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.successGreen.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      '局域网：${host.lanRelayEndpoint}/frame.jpg',
                      style: TextStyle(
                        color: AppTheme.primaryBlue,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '两端的信令服务器都需设置为 rdesk_server 地址',
                      style:
                          TextStyle(color: Colors.grey.shade500, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],

            // Debug info
            ..._debugInfoRows(context),

            if (host.previewFrame != null) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: host.previewFrame!.width > 0 &&
                          host.previewFrame!.height > 0
                      ? host.previewFrame!.width / host.previewFrame!.height
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
                        left: 10,
                        top: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.circle,
                                  color: Colors.redAccent, size: 8),
                              SizedBox(width: 6),
                              Text('实时预览',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Action buttons
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _ActionButton(
                  icon: Icons.security_rounded,
                  label: '申请录屏',
                  filled: true,
                  onPressed: host.busy ? null : host.requestPermission,
                ),
                _ActionButton(
                  icon: Icons.play_arrow_rounded,
                  label: host.guardModeEnabled ? '立即进入守护' : '启动服务',
                  onPressed: host.busy || !host.state.hasPermission
                      ? null
                      : host.startHosting,
                ),
                _ActionButton(
                  icon: Icons.stop_rounded,
                  label: host.guardModeEnabled ? '暂停守护' : '停止服务',
                  onPressed: host.busy || !host.state.isRunning
                      ? null
                      : host.stopHosting,
                ),
                _ActionButton(
                  icon: Icons.link_off_rounded,
                  label: '断开远控',
                  color: AppTheme.errorRed,
                  onPressed: host.busy || !host.canDisconnectViewers
                      ? null
                      : onDisconnect,
                ),
                _ActionButton(
                  icon: Icons.accessibility_new_rounded,
                  label: '无障碍',
                  onPressed: host.openAccessibilitySettings,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _debugInfoRows(BuildContext context) {
    final items = <MapEntry<String, String?>>[];
    if (host.lastRemoteTap != null) {
      items.add(MapEntry('远程点击', host.lastRemoteTap));
    }
    if (host.lastRemoteAction != null) {
      items.add(MapEntry('远程动作', host.lastRemoteAction));
    }
    if (host.lastRemoteGesture != null) {
      items.add(MapEntry('远程手势', host.lastRemoteGesture));
    }
    if (host.lastRemoteText != null) {
      items.add(MapEntry('远程文本', host.lastRemoteText));
    }
    if (host.lastRemoteClipboard != null) {
      items.add(MapEntry('远程剪贴板', host.lastRemoteClipboard));
    }
    if (items.isEmpty) return [];

    return [
      const SizedBox(height: 14),
      ...items.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Text('${e.key}：',
                    style:
                        TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    e.value!,
                    style: TextStyle(
                      color: AppTheme.primaryBlue,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          )),
    ];
  }
}

class _ChecklistTile extends StatelessWidget {
  final String label;
  final String description;
  final bool done;
  final String actionLabel;
  final VoidCallback? onPressed;

  const _ChecklistTile({
    required this.label,
    required this.description,
    required this.done,
    required this.actionLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = done ? AppTheme.successGreen : AppTheme.warningAmber;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(description,
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: Colors.grey.shade600)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: onPressed,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final Color? color;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.filled = false,
    this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.primaryBlue;
    if (filled) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 13)),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: onPressed != null ? c : null),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        foregroundColor: c,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(
            color: onPressed != null
                ? c.withValues(alpha: 0.3)
                : Colors.grey.shade300),
      ),
    );
  }
}
