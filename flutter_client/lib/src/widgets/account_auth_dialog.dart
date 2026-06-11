import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../utils/theme.dart';

Future<void> showAccountAuthDialog(
  BuildContext context, {
  required bool registerMode,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AccountAuthSheet(initialRegister: registerMode),
  );
}

class _AccountAuthSheet extends StatefulWidget {
  final bool initialRegister;

  const _AccountAuthSheet({required this.initialRegister});

  @override
  State<_AccountAuthSheet> createState() => _AccountAuthSheetState();
}

class _AccountAuthSheetState extends State<_AccountAuthSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialRegister ? 1 : 0,
    );
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() => _error = null);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  bool get _isRegister => _tabController.index == 1;

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
      Navigator.pop(context);
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
      Navigator.pop(context);
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1E2D) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Brand header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? const [Color(0xFF1C2440), Color(0xFF1A1E2D)]
                        : const [Color(0xFFEEF4FF), Color(0xFFF8FBFF)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: AppTheme.brandGradient,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.25),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.connected_tv_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'RDesk 账号',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '登录后可同步设备、快速发起远程连接',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: isDark ? Colors.white60 : AppTheme.textMuted,
                          ),
                    ),
                  ],
                ),
              ),

              // Tab bar
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      color: isDark ? const Color(0xFF2A2E3E) : Colors.white,
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerHeight: 0,
                    labelColor: isDark ? Colors.white : AppTheme.textDark,
                    unselectedLabelColor:
                        isDark ? Colors.white54 : AppTheme.textMuted,
                    labelStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    tabs: const [Tab(text: '登录'), Tab(text: '注册')],
                  ),
                ),
              ),

              // Form fields
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _usernameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                        hintText: '输入用户名',
                        labelText: '账号',
                      ),
                    ),

                    // Display name field (register only)
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      child: AnimatedBuilder(
                        animation: _tabController,
                        builder: (context, _) {
                          if (!_isRegister) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: TextField(
                              controller: _displayNameController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                prefixIcon:
                                    Icon(Icons.badge_outlined, size: 20),
                                hintText: '可选，留空则使用账号名',
                                labelText: '显示名称',
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 14),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        prefixIcon:
                            const Icon(Icons.lock_outline_rounded, size: 20),
                        hintText: '至少 6 位',
                        labelText: '密码',
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                        ),
                      ),
                    ),

                    // Error message
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: _error != null
                          ? Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color:
                                      AppTheme.errorRed.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline_rounded,
                                        color: AppTheme.errorRed, size: 18),
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
                            )
                          : const SizedBox.shrink(),
                    ),

                    const SizedBox(height: 24),

                    // Submit button
                    SizedBox(
                      height: 52,
                      child: AnimatedBuilder(
                        animation: _tabController,
                        builder: (context, _) {
                          return DecoratedBox(
                            decoration: BoxDecoration(
                              gradient:
                                  _loading ? null : AppTheme.brandGradient,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: _loading
                                  ? null
                                  : [
                                      BoxShadow(
                                        color: AppTheme.primaryBlue
                                            .withValues(alpha: 0.25),
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
                                disabledBackgroundColor: isDark
                                    ? Colors.grey.shade800
                                    : Colors.grey.shade300,
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
                          );
                        },
                      ),
                    ),

                    AnimatedBuilder(
                      animation: _tabController,
                      builder: (context, _) {
                        if (_isRegister) {
                          return const SizedBox.shrink();
                        }
                        return Consumer<AuthProvider>(
                          builder: (context, auth, _) {
                            if (!auth.canUseBiometricLogin) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: SizedBox(
                                height: 48,
                                child: OutlinedButton.icon(
                                  onPressed:
                                      _loading ? null : _submitWithBiometrics,
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
                        );
                      },
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wrapper that rebuilds when the given [Listenable] changes.
class AnimatedBuilder extends StatefulWidget {
  final Listenable animation;
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  const AnimatedBuilder({
    super.key,
    required this.animation,
    required this.builder,
    this.child,
  });

  @override
  State<AnimatedBuilder> createState() => _AnimatedBuilderState();
}

class _AnimatedBuilderState extends State<AnimatedBuilder> {
  @override
  void initState() {
    super.initState();
    widget.animation.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(AnimatedBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeListener(_onChanged);
      widget.animation.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.animation.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.child);
}
