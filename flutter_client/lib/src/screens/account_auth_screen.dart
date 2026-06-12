import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../providers/auth_provider.dart';
import '../utils/theme.dart';
import '../widgets/account_auth_dialog.dart';

String accountAuthRoute(AccountAuthMode mode, {String? redirect}) {
  final path = switch (mode) {
    AccountAuthMode.login => '/login',
    AccountAuthMode.register => '/register',
  };
  final safeRedirect = _safeRedirectPath(redirect);
  return Uri(
    path: path,
    queryParameters: safeRedirect == null
        ? null
        : <String, String>{'redirect': safeRedirect},
  ).toString();
}

class AccountAuthScreen extends StatelessWidget {
  final AccountAuthMode mode;
  final String? redirect;

  const AccountAuthScreen({
    super.key,
    required this.mode,
    this.redirect,
  });

  bool get _isRegister => mode == AccountAuthMode.register;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final redirectPath = _safeRedirectPath(redirect) ?? '/me';

    return Scaffold(
      appBar: AppBar(
        title: Text(_isRegister ? '注册账号' : '登录账号'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Consumer<AuthProvider>(
              builder: (context, auth, _) {
                final session = auth.session;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
                  shrinkWrap: true,
                  children: [
                    _AuthHeader(isRegister: _isRegister, isDark: isDark),
                    const SizedBox(height: 28),
                    if (session != null)
                      _SignedInPanel(
                        session: session,
                        onContinue: () => context.go(redirectPath),
                        onLogout: auth.logout,
                      )
                    else ...[
                      AccountAuthForm(
                        mode: mode,
                        onAuthenticated: () => context.go(redirectPath),
                      ),
                      const SizedBox(height: 18),
                      _ModeSwitchLink(
                        isRegister: _isRegister,
                        redirectPath: redirectPath,
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthHeader extends StatelessWidget {
  final bool isRegister;
  final bool isDark;

  const _AuthHeader({
    required this.isRegister,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: AppTheme.brandGradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryBlue.withValues(alpha: 0.22),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(
            isRegister ? Icons.person_add_rounded : Icons.connected_tv_rounded,
            color: Colors.white,
            size: 30,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          isRegister ? '创建 RDesk 账号' : '登录 RDesk 账号',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          isRegister ? '注册后可同步设备，并在多端快速发起远程连接。' : '登录后可同步设备、地址簿和远程连接状态。',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.white60 : AppTheme.textMuted,
              ),
        ),
      ],
    );
  }
}

class _SignedInPanel extends StatelessWidget {
  final AccountSession session;
  final VoidCallback onContinue;
  final Future<void> Function() onLogout;

  const _SignedInPanel({
    required this.session,
    required this.onContinue,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: AppTheme.primaryBlue,
                child: Icon(Icons.person_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.displayName.isEmpty
                          ? session.username
                          : session.displayName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      session.username,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textMuted,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onContinue,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('继续使用'),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () async => onLogout(),
          child: const Text('退出当前账号'),
        ),
      ],
    );
  }
}

class _ModeSwitchLink extends StatelessWidget {
  final bool isRegister;
  final String redirectPath;

  const _ModeSwitchLink({
    required this.isRegister,
    required this.redirectPath,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(isRegister ? '已有账号？' : '还没有账号？'),
        TextButton(
          onPressed: () => context.go(
            accountAuthRoute(
              isRegister ? AccountAuthMode.login : AccountAuthMode.register,
              redirect: redirectPath,
            ),
          ),
          child: Text(isRegister ? '去登录' : '去注册'),
        ),
      ],
    );
  }
}

String? _safeRedirectPath(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  final path = value.trim();
  if (!path.startsWith('/') || path.startsWith('//')) {
    return null;
  }
  if (path == '/login' || path == '/register') {
    return null;
  }
  return path;
}
