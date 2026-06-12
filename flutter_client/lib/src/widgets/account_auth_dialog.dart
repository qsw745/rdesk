import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../utils/theme.dart';

enum AccountAuthMode { login, register }

class AccountAuthForm extends StatefulWidget {
  final AccountAuthMode mode;
  final VoidCallback onAuthenticated;

  const AccountAuthForm({
    super.key,
    required this.mode,
    required this.onAuthenticated,
  });

  @override
  State<AccountAuthForm> createState() => _AccountAuthFormState();
}

class _AccountAuthFormState extends State<AccountAuthForm> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  bool get _isRegister => widget.mode == AccountAuthMode.register;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty) {
      setState(() => _error = '请输入账号');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = '密码至少需要 6 位');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final auth = context.read<AuthProvider>();
    final ok = _isRegister
        ? await auth.register(
            username: username,
            password: password,
            displayName: _displayNameController.text.trim(),
          )
        : await auth.login(username: username, password: password);

    if (!mounted) return;

    if (ok) {
      widget.onAuthenticated();
    } else {
      setState(() {
        _loading = false;
        _error = auth.error ?? '操作失败，请重试';
      });
    }
  }

  Future<void> _submitWithBiometrics() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final auth = context.read<AuthProvider>();
    final ok = await auth.loginWithBiometrics();
    if (!mounted) return;

    if (ok) {
      widget.onAuthenticated();
    } else {
      setState(() {
        _loading = false;
        _error = auth.error ?? '生物识别登录失败，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _usernameController,
          textInputAction: TextInputAction.next,
          enabled: !_loading,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
            hintText: '输入用户名',
            labelText: '账号',
          ),
        ),
        if (_isRegister) ...[
          const SizedBox(height: 14),
          TextField(
            controller: _displayNameController,
            textInputAction: TextInputAction.next,
            enabled: !_loading,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.badge_outlined, size: 20),
              hintText: '可选，留空则使用账号名',
              labelText: '显示名称',
            ),
          ),
        ],
        const SizedBox(height: 14),
        TextField(
          controller: _passwordController,
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          enabled: !_loading,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
            hintText: '至少 6 位',
            labelText: '密码',
            suffixIcon: IconButton(
              onPressed:
                  _loading ? null : () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: _error == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.errorRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: AppTheme.errorRed,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: AppTheme.errorRed,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: _loading ? null : AppTheme.brandGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: _loading
                  ? null
                  : [
                      BoxShadow(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                disabledBackgroundColor:
                    isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _isRegister ? '注册并登录' : '登录',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
        if (!_isRegister)
          Consumer<AuthProvider>(
            builder: (context, auth, _) {
              if (!auth.canUseBiometricLogin) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _submitWithBiometrics,
                    icon: Icon(
                      auth.biometricLabel.contains('Face')
                          ? Icons.face_rounded
                          : Icons.fingerprint_rounded,
                    ),
                    label: Text('使用${auth.biometricLabel}登录'),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
