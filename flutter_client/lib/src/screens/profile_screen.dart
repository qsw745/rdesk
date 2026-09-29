import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/wake_provider.dart';
import '../screens/account_auth_screen.dart';
import '../services/wake_agent_channel.dart';
import '../ui/components.dart';
import '../ui/device_actions.dart';
import '../ui/tokens.dart';
import '../utils/theme.dart';
import '../utils/platform_capabilities.dart';
import '../widgets/account_auth_dialog.dart';

/// "我的" on phones, "账号" on desktop: account, shortcuts and settings.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final desktop = PlatformCapabilities.current.isDesktop;
    final auth = context.watch<AuthProvider>();
    final wake = context.watch<WakeProvider>();
    final session = auth.session;
    final devices = watchDeviceDirectory(context);
    final online = devices.where((e) => e.online).length;

    String wakeSubtitle() {
      if (!auth.isLoggedIn) return '登录后使用';
      if (wake.helper.enabled) {
        final code = wake.helper.errorCode;
        return code == null ? '本机正在作为家中开机助手' : describeHelperError(code);
      }
      if (wake.targets.isEmpty) return '电脑关机也能用手机开机';
      return '${wake.targets.length} 台电脑可远程开机';
    }

    return RdPage(
      title: desktop ? '账号' : '我的',
      maxWidth: 760,
      children: [
        _AccountHeader(
          name: session == null
              ? null
              : session.displayName.isNotEmpty
                  ? session.displayName
                  : session.username,
          username: session?.username,
          summary: session == null
              ? '登录后，同一账号下的设备会自动同步'
              : '${devices.length} 台设备 · $online 台在线',
          onLogin: () => context
              .push(accountAuthRoute(AccountAuthMode.login, redirect: '/me')),
          onRegister: () => context.push('/register?redirect=%2Fme'),
        ),
        const SizedBox(height: 24),
        RdGroup(children: [
          if (!desktop)
            RdTile(
                icon: Icons.power_settings_new_rounded,
                tone: RdTone.power,
                title: '远程开机',
                subtitle: wakeSubtitle(),
                onTap: () => context.push('/wake')),
          RdTile(
              icon: Icons.history_rounded,
              title: '连接记录',
              onTap: () => context.push('/logs')),
          RdTile(
              icon: Icons.star_rounded,
              tone: RdTone.warning,
              title: '收藏与分组',
              onTap: () => context.push('/saved')),
          if (!desktop)
            RdTile(
                icon: Icons.touch_app_rounded,
                title: '操作手势',
                onTap: () => context.push('/gesture-guide')),
        ]),
        if (!desktop) ...[
          const SizedBox(height: 24),
          const RdSectionHeader('设置'),
          RdGroup(children: [
            RdTile(
                icon: Icons.tune_rounded,
                tone: RdTone.neutral,
                title: '通用',
                subtitle: '外观、画质与操作习惯',
                onTap: () => context.push('/settings?section=general')),
            RdTile(
                icon: Icons.shield_rounded,
                tone: RdTone.online,
                title: '安全',
                subtitle: '永久验证码与受信任设备',
                onTap: () => context.push('/settings?section=security')),
            RdTile(
                icon: Icons.public_rounded,
                tone: RdTone.neutral,
                title: '网络',
                subtitle: '服务器地址',
                onTap: () => context.push('/settings?section=network')),
            RdTile(
                icon: Icons.info_rounded,
                tone: RdTone.neutral,
                title: '关于随控',
                onTap: () => context.push('/settings?section=about')),
          ]),
        ],
        if (session != null) ...[
          const SizedBox(height: 24),
          const RdSectionHeader('账号与安全'),
          RdGroup(children: [
            if (_supportsBiometricPlatform)
              RdTile(
                icon: Icons.fingerprint_rounded,
                title: '${auth.biometricLabel}登录',
                trailing: Switch.adaptive(
                    value: auth.biometricEnabled,
                    onChanged: auth.busy
                        ? null
                        : (value) async {
                            final ok = await auth.setBiometricEnabled(value);
                            if (!context.mounted) return;
                            if (!ok && auth.error != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(auth.error!)));
                            }
                          }),
              ),
            RdTile(
                icon: Icons.logout_rounded,
                tone: RdTone.neutral,
                title: '退出登录',
                chevron: false,
                onTap: auth.busy ? null : auth.logout),
            RdTile(
                icon: Icons.person_remove_rounded,
                tone: RdTone.danger,
                title: '注销账号',
                subtitle: '永久删除账号及云端设备记录',
                onTap: () => _confirmDeleteAccount(context, auth)),
          ]),
        ],
      ],
    );
  }
}

bool get _supportsBiometricPlatform {
  if (kIsWeb) return false;
  return Platform.isIOS || Platform.isMacOS;
}

class _AccountHeader extends StatelessWidget {
  final String? name, username;
  final String summary;
  final VoidCallback onLogin, onRegister;
  const _AccountHeader(
      {required this.name,
      required this.username,
      required this.summary,
      required this.onLogin,
      required this.onRegister});

  @override
  Widget build(BuildContext context) {
    final p = RdPalette.of(context);
    final t = Theme.of(context).textTheme;
    final signedIn = name != null;
    return RdCard(
      padding: const EdgeInsets.all(20),
      radius: Rd.radiusLg,
      child: Row(children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: signedIn ? p.brand : p.surfaceMuted,
          child: signedIn
              ? Text(name!.characters.first.toUpperCase(),
                  style: t.headlineSmall!.copyWith(color: Colors.white))
              : Icon(Icons.person_rounded, size: 32, color: p.inkTertiary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(signedIn ? name! : '未登录', style: t.titleLarge),
            if (signedIn && username != null && username != name)
              Text('@$username', style: t.bodySmall),
            const SizedBox(height: 4),
            Text(summary, style: t.bodySmall),
            if (!signedIn) ...[
              const SizedBox(height: 14),
              Wrap(spacing: 10, runSpacing: 8, children: [
                FilledButton(onPressed: onLogin, child: const Text('登录')),
                OutlinedButton(onPressed: onRegister, child: const Text('注册')),
              ]),
            ],
          ]),
        ),
      ]),
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
