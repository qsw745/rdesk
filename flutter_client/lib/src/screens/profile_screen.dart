import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../screens/account_auth_screen.dart';
import '../utils/platform_capabilities.dart';
import '../utils/theme.dart';
import '../widgets/account_auth_dialog.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cap = PlatformCapabilities.current;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = Theme.of(context).colorScheme.surface;
    return Scaffold(
        appBar: AppBar(
            title: Text(cap.isDesktop ? '账号' : '我的'),
            automaticallyImplyLeading: false),
        body: Consumer<AuthProvider>(builder: (context, auth, _) {
          final session = auth.session;
          return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(padding: const EdgeInsets.all(24), children: [
                    _ProfileHeaderCard(
                        session: session,
                        deviceCount: auth.devices.length,
                        isDark: isDark,
                        onLogin: () => context.push(accountAuthRoute(
                            AccountAuthMode.login,
                            redirect: '/me'))),
                    if (session == null)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Wrap(spacing: 12, runSpacing: 8, children: [
                            FilledButton(
                                onPressed: () =>
                                    context.push('/login?redirect=%2Fme'),
                                child: const Text('登录账号')),
                            OutlinedButton(
                                onPressed: () =>
                                    context.push('/register?redirect=%2Fme'),
                                child: const Text('注册账号')),
                          ])),
                    if (!cap.isDesktop) ...[
                      const SizedBox(height: 16),
                      const _SectionLabel(label: '设置'),
                      const SizedBox(height: 8),
                      _MenuGroup(cardBg: cardBg, isDark: isDark, children: [
                        _MenuItem(
                            icon: Icons.tune,
                            iconColor: AppTheme.primaryBlue,
                            title: '常规',
                            onTap: () =>
                                context.push('/settings?section=general')),
                        _MenuItem(
                            icon: Icons.shield_outlined,
                            iconColor: AppTheme.primaryBlue,
                            title: '安全',
                            onTap: () =>
                                context.push('/settings?section=security')),
                        _MenuItem(
                            icon: Icons.language,
                            iconColor: AppTheme.primaryBlue,
                            title: '网络',
                            onTap: () =>
                                context.push('/settings?section=network')),
                      ]),
                      const SizedBox(height: 16),
                      _MenuGroup(cardBg: cardBg, isDark: isDark, children: [
                        _MenuItem(
                            icon: Icons.touch_app_outlined,
                            iconColor: AppTheme.primaryBlue,
                            title: '操作手势',
                            onTap: () => context.push('/gesture-guide')),
                        _MenuItem(
                            icon: Icons.history,
                            iconColor: AppTheme.primaryBlue,
                            title: '连接记录',
                            onTap: () => context.push('/logs')),
                        _MenuItem(
                            icon: Icons.info_outline,
                            iconColor: AppTheme.primaryBlue,
                            title: '关于 RDesk',
                            onTap: () =>
                                context.push('/settings?section=about')),
                      ]),
                    ],
                    if (session != null) ...[
                      const SizedBox(height: 20),
                      _MenuGroup(cardBg: cardBg, isDark: isDark, children: [
                        if (_supportsBiometricPlatform)
                          _MenuItem(
                              icon: Icons.fingerprint,
                              iconColor: AppTheme.primaryBlue,
                              title: '${auth.biometricLabel}登录',
                              onTap: null,
                              trailing: Switch.adaptive(
                                  value: auth.biometricEnabled,
                                  onChanged: auth.busy
                                      ? null
                                      : (value) async {
                                          final ok = await auth
                                              .setBiometricEnabled(value);
                                          if (!context.mounted) return;
                                          if (!ok && auth.error != null) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(
                                                    content:
                                                        Text(auth.error!)));
                                          }
                                        })),
                        _MenuItem(
                            icon: Icons.logout,
                            iconColor: AppTheme.errorRed,
                            title: '退出登录',
                            onTap: auth.logout),
                        _MenuItem(
                            icon: Icons.person_remove_outlined,
                            iconColor: AppTheme.errorRed,
                            title: '注销账号',
                            subtitle: '永久删除账号及云端设备记录',
                            onTap: () => _confirmDeleteAccount(context, auth)),
                      ]),
                    ],
                  ])));
        }));
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : AppTheme.primaryBlue.withValues(alpha: 0.10),
        ),
      ),
      child: InkWell(
        onTap: session == null ? onLogin : null,
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppTheme.primaryBlue,
                shape: BoxShape.circle,
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

/// 注销账号确认流程：先展示后果，再要求输入密码二次确认。
///
/// 删除不可逆，因此不使用「一键删除」，必须让用户明确看到会失去什么。
Future<void> _confirmDeleteAccount(
  BuildContext context,
  AuthProvider auth,
) async {
  final deleted = await showDialog<bool>(
    context: context,
    builder: (ctx) => _DeleteAccountDialog(auth: auth),
  );
  if (deleted != true || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('账号已注销'),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.auth});

  final AuthProvider auth;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      setState(() => _error = '请输入密码以确认身份');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    final ok = await widget.auth.deleteAccount(password);
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _submitting = false;
      _error = widget.auth.error ?? '注销失败，请稍后重试';
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.auth.session;
    return AlertDialog(
      title: const Text('注销账号'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (session != null)
              Text(
                '账号：${session.username}',
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            const SizedBox(height: 10),
            const Text(
              '注销后将永久删除：',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 6),
            const Text(
              '· 你的账号与登录凭据\n'
              '· 云端保存的设备列表与在线状态\n'
              '· 全部已登录设备的登录状态',
              style: TextStyle(fontSize: 13.5, height: 1.6),
            ),
            const SizedBox(height: 10),
            const Text(
              '此操作不可撤销，账号无法恢复。本机的连接历史需另行清除。',
              style: TextStyle(fontSize: 13.5, color: AppTheme.errorRed),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: _obscure,
              enabled: !_submitting,
              autofocus: true,
              onSubmitted: (_) => _submitting ? null : _submit(),
              decoration: InputDecoration(
                labelText: '请输入密码确认',
                isDense: true,
                border: const OutlineInputBorder(),
                errorText: _error,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.errorRed),
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('确认注销'),
        ),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _MenuItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onTap,
    this.subtitle,
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
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(
                fontSize: 13.5,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded, size: 20),
    );
  }
}
