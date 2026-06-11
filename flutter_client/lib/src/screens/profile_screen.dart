import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';
import '../widgets/account_auth_dialog.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        automaticallyImplyLeading: false,
      ),
      body: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          final session = auth.session;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              // --- Profile header card ---
              _ProfileHeaderCard(
                session: session,
                deviceCount: auth.devices.length,
                isDark: isDark,
                onLogin: () =>
                    showAccountAuthDialog(context, registerMode: false),
              ),

              if (session == null) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: () => showAccountAuthDialog(context,
                              registerMode: false),
                          icon: const Icon(Icons.login_rounded, size: 18),
                          label: const Text('登录账号'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: () => showAccountAuthDialog(context,
                              registerMode: true),
                          icon: const Icon(Icons.person_add_rounded, size: 18),
                          label: const Text('注册账号'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 14),

              // --- Quick function grid (2x3) ---
              _QuickFunctionGrid(isDark: isDark, cardBg: cardBg),

              const SizedBox(height: 14),

              // --- Settings group: Basic ---
              const _SectionLabel(label: '基础设置'),
              const SizedBox(height: 6),
              _MenuGroup(
                cardBg: cardBg,
                isDark: isDark,
                children: [
                  _MenuItem(
                    icon: Icons.settings_outlined,
                    iconColor: AppTheme.primaryBlue,
                    title: '通用设置',
                    onTap: () => context.push('/settings'),
                  ),
                  _MenuItem(
                    icon: Icons.history_rounded,
                    iconColor: AppTheme.accentPurple,
                    title: '连接历史',
                    onTap: () => context.push('/logs'),
                  ),
                  if (session != null)
                    _MenuItem(
                      icon: Icons.sync_rounded,
                      iconColor: const Color(0xFF2BBFA0),
                      title: '刷新设备列表',
                      trailing: auth.busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                      onTap: auth.busy ? null : auth.refreshDevices,
                    ),
                ],
              ),

              const SizedBox(height: 14),

              // --- Settings group: Security ---
              const _SectionLabel(label: '安全中心'),
              const SizedBox(height: 6),
              _MenuGroup(
                cardBg: cardBg,
                isDark: isDark,
                children: [
                  _MenuItem(
                    icon: Icons.settings_remote_rounded,
                    iconColor: AppTheme.warningAmber,
                    title: '无人值守设置',
                    onTap: () => context.push('/unattended-setup'),
                  ),
                  if (session != null && _supportsBiometricPlatform)
                    _MenuItem(
                      icon: Icons.fingerprint_rounded,
                      iconColor: const Color(0xFF3AA56B),
                      title: '${auth.biometricLabel}登录',
                      trailing: Switch.adaptive(
                        value: auth.biometricEnabled,
                        onChanged: auth.busy
                            ? null
                            : (value) async {
                                final ok =
                                    await auth.setBiometricEnabled(value);
                                if (!context.mounted) return;
                                if (!ok && auth.error != null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(auth.error!),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                      ),
                      // Keep toggle changes on the Switch only.
                      // ListTile onTap + Switch onChanged can trigger twice and
                      // immediately revert the just-enabled state.
                      onTap: null,
                    ),
                  if (session != null)
                    _MenuItem(
                      icon: Icons.logout_rounded,
                      iconColor: AppTheme.errorRed,
                      title: '退出登录',
                      onTap: auth.logout,
                    ),
                ],
              ),

              const SizedBox(height: 14),

              // --- Help ---
              const _SectionLabel(label: '帮助中心'),
              const SizedBox(height: 6),
              _MenuGroup(
                cardBg: cardBg,
                isDark: isDark,
                children: [
                  _MenuItem(
                    icon: Icons.info_outline_rounded,
                    iconColor: Colors.blueGrey,
                    title: '关于 RDesk',
                    onTap: () {
                      showAboutDialog(
                        context: context,
                        applicationName: AppConstants.appName,
                        applicationVersion: 'v${AppConstants.version}',
                        applicationIcon: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: AppTheme.brandGradient,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.connected_tv_rounded,
                              color: Colors.white, size: 28),
                        ),
                      );
                    },
                  ),
                ],
              ),

              // App version footer
              const SizedBox(height: 32),
              Center(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: AppTheme.brandGradient,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.15),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.connected_tv_rounded,
                          color: Colors.white, size: 22),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      AppConstants.appName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white54 : AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'v${AppConstants.version}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.grey.shade400,
                      ),
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
}

bool get _supportsBiometricPlatform {
  if (kIsWeb) return false;
  return Platform.isIOS || Platform.isMacOS;
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white54 : AppTheme.textMuted,
        ),
      ),
    );
  }
}

class _ProfileHeaderCard extends StatelessWidget {
  final dynamic session;
  final int deviceCount;
  final bool isDark;
  final VoidCallback onLogin;

  const _ProfileHeaderCard({
    required this.session,
    required this.deviceCount,
    required this.isDark,
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    final name = session?.displayName as String? ?? '未登录账号';
    final subtitle = session == null ? '点击登录以同步你的设备' : '个人设备: $deviceCount 台在线';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF1C2440), Color(0xFF151B2D)]
              : const [Color(0xFFE0EDFF), Color(0xFFF0F6FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : AppTheme.primaryBlue.withValues(alpha: 0.10),
        ),
      ),
      child: InkWell(
        onTap: session == null ? onLogin : null,
        borderRadius: BorderRadius.circular(20),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: AppTheme.brandGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(Icons.person_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white54 : AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (session == null)
              Icon(
                Icons.chevron_right_rounded,
                color: isDark ? Colors.white38 : AppTheme.textMuted,
              ),
          ],
        ),
      ),
    );
  }
}

class _QuickFunctionGrid extends StatelessWidget {
  final bool isDark;
  final Color cardBg;

  const _QuickFunctionGrid({
    required this.isDark,
    required this.cardBg,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _QuickItem(Icons.tune_rounded, '连接设置', const Color(0xFF4A90D9),
          () => context.push('/connection-settings')),
      _QuickItem(Icons.touch_app_rounded, '操作手势', const Color(0xFFE8823A),
          () => context.push('/gesture-guide')),
      _QuickItem(Icons.keyboard_rounded, '快捷键', const Color(0xFF6C5CE7),
          () => context.push('/shortcut-guide')),
      _QuickItem(Icons.folder_rounded, '我的文件', const Color(0xFF2BBFA0),
          () => context.push('/logs')),
      _QuickItem(Icons.settings_remote_rounded, '无人值守', const Color(0xFFE05B6E),
          () => context.push('/unattended-setup')),
      _QuickItem(Icons.info_outline_rounded, '关于', Colors.blueGrey, () {
        showAboutDialog(
          context: context,
          applicationName: AppConstants.appName,
          applicationVersion: 'v${AppConstants.version}',
        );
      }),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          if (compact) {
            return GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.2,
              mainAxisSpacing: 0,
              crossAxisSpacing: 0,
              children: items.map((item) {
                return _QuickFunctionItem(
                  icon: item.icon,
                  label: item.label,
                  color: item.color,
                  isDark: isDark,
                  onTap: item.onTap,
                );
              }).toList(),
            );
          }

          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 170,
              mainAxisExtent: 128,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemBuilder: (context, index) {
              final item = items[index];
              return _QuickFunctionItem(
                icon: item.icon,
                label: item.label,
                color: item.color,
                isDark: isDark,
                onTap: item.onTap,
              );
            },
          );
        },
      ),
    );
  }
}

class _QuickItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickItem(this.icon, this.label, this.color, this.onTap);
}

class _QuickFunctionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _QuickFunctionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuGroup extends StatelessWidget {
  final Color cardBg;
  final bool isDark;
  final List<Widget> children;

  const _MenuGroup({
    required this.cardBg,
    required this.isDark,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.04),
        ),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 56,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey.shade100,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _MenuItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      enabled: onTap != null,
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded, size: 20),
    );
  }
}
