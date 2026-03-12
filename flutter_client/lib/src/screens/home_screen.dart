import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/connection_info.dart';
import '../models/session.dart';
import '../providers/auth_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/theme.dart';
import '../widgets/device_id_display.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _deviceIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _accountUsernameController = TextEditingController();
  final _accountPasswordController = TextEditingController();
  final _accountDisplayNameController = TextEditingController();
  bool _showPassword = false;
  bool _didApplyPendingQuickConnect = false;

  @override
  void initState() {
    super.initState();
    context.read<ConnectionProvider>().initialize();
  }

  @override
  void dispose() {
    _deviceIdController.dispose();
    _passwordController.dispose();
    _accountUsernameController.dispose();
    _accountPasswordController.dispose();
    _accountDisplayNameController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final deviceId = _deviceIdController.text.trim();
    await _connectToPeer(deviceId);
  }

  Future<void> _connectToPeer(String deviceId) async {
    final password = _passwordController.text.trim();
    final messenger = ScaffoldMessenger.of(context);

    if (deviceId.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('请输入设备ID'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    final provider = context.read<ConnectionProvider>();
    final settingsProvider = context.read<SettingsProvider>();
    final sessionProvider = context.read<SessionProvider>();
    final sessionId = await provider.connect(deviceId, password);
    if (sessionId != null && mounted) {
      await settingsProvider.refreshTrustedPeers();
      if (!mounted) return;
      sessionProvider.setSession(
        SessionInfo(
          sessionId: sessionId,
          peerId: deviceId,
          peerHostname: '远程设备 $deviceId',
          peerOs: '未知系统',
          state: SessionState.active,
          connectedAt: DateTime.now(),
          latencyMs: 42,
        ),
        accessPassword: password,
      );
      context.go('/remote/$sessionId');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_didApplyPendingQuickConnect) {
      _didApplyPendingQuickConnect = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final peerId =
            context.read<ConnectionProvider>().consumeQuickConnectPeerId();
        if (peerId != null && peerId.isNotEmpty) {
          _applyQuickConnectPeer(peerId);
        }
      });
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Column(
        children: [
          // ── Header ──
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: AppTheme.headerGradient,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: const Icon(Icons.connected_tv_rounded,
                          color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'RDesk',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '安全高效的跨平台远程控制',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: IconButton(
                        onPressed: () => context.go('/settings'),
                        icon: const Icon(Icons.settings_outlined,
                            color: Colors.white, size: 22),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Body ──
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 540),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Device ID card
                      Consumer<ConnectionProvider>(
                        builder: (context, provider, _) {
                          return DeviceIdDisplay(
                            deviceId:
                                provider.localDevice?.deviceId ?? '000000000',
                            temporaryPassword: provider.temporaryPassword,
                            onRefreshPassword: provider.refreshPassword,
                          );
                        },
                      ),
                      const SizedBox(height: 20),

                      Consumer2<ConnectionProvider, SettingsProvider>(
                        builder: (context, provider, settings, _) {
                          final device = provider.localDevice;
                          final trustedCount = settings.trustedPeers.length;
                          return _OverviewCard(
                            hostname: device?.hostname ?? '当前设备',
                            platformLabel: device?.os ?? '未知平台',
                            autoAccept: settings.autoAccept,
                            trustedCount: trustedCount,
                          );
                        },
                      ),
                      const SizedBox(height: 20),

                      _buildAccountSection(context, isDark),
                      const SizedBox(height: 20),

                      // Connect card
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color:
                              isDark ? const Color(0xFF1E1E2E) : Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.04),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: isDark ? 0.2 : 0.04),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryBlue
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.link_rounded,
                                      color: AppTheme.primaryBlue, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '连接远程设备',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _deviceIdController,
                              decoration: const InputDecoration(
                                labelText: '设备ID',
                                hintText: '输入对方9位设备ID',
                                prefixIcon:
                                    Icon(Icons.devices_rounded, size: 20),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(9),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _passwordController,
                              decoration: InputDecoration(
                                labelText: '连接密码',
                                hintText: '输入连接密码',
                                prefixIcon:
                                    const Icon(Icons.lock_outline, size: 20),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _showPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 20,
                                  ),
                                  onPressed: () => setState(
                                      () => _showPassword = !_showPassword),
                                ),
                              ),
                              obscureText: !_showPassword,
                            ),
                            const SizedBox(height: 20),
                            Consumer<ConnectionProvider>(
                              builder: (context, provider, _) {
                                final isConnecting = provider.connectionState ==
                                    SessionState.connecting;
                                return Container(
                                  height: 52,
                                  decoration: BoxDecoration(
                                    gradient: isConnecting
                                        ? null
                                        : AppTheme.brandGradient,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: isConnecting
                                        ? null
                                        : [
                                            BoxShadow(
                                              color: AppTheme.primaryBlue
                                                  .withValues(alpha: 0.3),
                                              blurRadius: 12,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: isConnecting ? null : _connect,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      disabledBackgroundColor:
                                          Colors.grey.shade300,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: isConnecting
                                        ? const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              SizedBox(width: 12),
                                              Text(
                                                '连接中...',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          )
                                        : const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.arrow_forward_rounded,
                                                  color: Colors.white,
                                                  size: 20),
                                              SizedBox(width: 8),
                                              Text(
                                                '连接',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                );
                              },
                            ),
                            Consumer<ConnectionProvider>(
                              builder: (context, provider, _) {
                                if (provider.errorMessage == null) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: AppTheme.errorRed
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: AppTheme.errorRed
                                            .withValues(alpha: 0.2),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.error_outline_rounded,
                                            color: AppTheme.errorRed, size: 20),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            provider.errorMessage!,
                                            style: const TextStyle(
                                              color: AppTheme.errorRed,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Recent connections
                      Consumer<ConnectionProvider>(
                        builder: (context, provider, _) {
                          final records =
                              provider.recentConnections.take(3).toList();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.schedule_rounded,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.grey.shade600,
                                      size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    '最近连接',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              if (records.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 40, horizontal: 24),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF1E1E2E)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.05)
                                          : Colors.black
                                              .withValues(alpha: 0.04),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryBlue
                                              .withValues(alpha: 0.08),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.devices_other_rounded,
                                          size: 32,
                                          color: AppTheme.primaryBlue
                                              .withValues(alpha: 0.5),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        '暂无连接记录',
                                        style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '连接成功后会自动记录在这里',
                                        style: TextStyle(
                                          color: Colors.grey.shade400,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                Column(
                                  children: records.map((record) {
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
                                      child: _RecentConnectionTile(
                                        record: record,
                                        onTap: () =>
                                            _handleRecentConnectionTap(record),
                                      ),
                                    );
                                  }).toList(),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 20),

                      // Quick actions
                      Row(
                        children: [
                          _QuickAction(
                            icon: Icons.history_rounded,
                            label: '连接历史',
                            onTap: () => context.go('/logs'),
                          ),
                          const SizedBox(width: 10),
                          _QuickAction(
                            icon: Icons.folder_outlined,
                            label: '文件管理',
                            onTap: () =>
                                ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('连接成功后可进入文件管理'),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _QuickAction(
                            icon: Icons.settings_outlined,
                            label: '设置',
                            onTap: () => context.go('/settings'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountSection(BuildContext context, bool isDark) {
    return Consumer2<AuthProvider, ConnectionProvider>(
      builder: (context, auth, connection, _) {
        final session = auth.session;
        final localDeviceId = connection.localDevice?.deviceId;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.04),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.successGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.account_circle_outlined,
                      color: AppTheme.successGreen,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      session == null ? '账号设备' : '我的设备',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (session != null)
                    IconButton(
                      onPressed: auth.busy ? null : auth.refreshDevices,
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: '刷新设备',
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (session == null) ...[
                Text(
                  '登录同一个账号后，可在这里看到该账号下当前在线的设备，便于快速发起远程连接。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.white70 : AppTheme.textMuted,
                      ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: auth.busy
                            ? null
                            : () => _showAccountDialog(
                                  context,
                                  registerMode: false,
                                ),
                        child: const Text('登录账号'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: auth.busy
                            ? null
                            : () => _showAccountDialog(
                                  context,
                                  registerMode: true,
                                ),
                        child: const Text('注册账号'),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.displayName,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '@${session.username}',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: isDark
                                          ? Colors.white70
                                          : AppTheme.textMuted,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: auth.busy ? null : auth.logout,
                      icon: const Icon(Icons.logout_rounded, size: 16),
                      label: const Text('退出'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (auth.error != null && auth.error!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      auth.error!,
                      style: const TextStyle(
                        color: AppTheme.errorRed,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (auth.busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (auth.devices.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      '该账号下暂时没有在线设备。已登录的设备开始共享后，会自动出现在这里。',
                      style: TextStyle(fontSize: 13),
                    ),
                  )
                else
                  Column(
                    children: auth.devices.map((device) {
                      final isCurrent = device.deviceId == localDeviceId;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _AccountDeviceTile(
                          hostname: device.hostname,
                          deviceId: device.deviceId,
                          platform: device.platform,
                          isCurrent: isCurrent,
                          updatedAt: device.updatedAt,
                          onTap: isCurrent
                              ? null
                              : () => _handleAccountDeviceTap(device.deviceId),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAccountDialog(
    BuildContext context, {
    required bool registerMode,
  }) async {
    var obscure = true;
    if (!registerMode) {
      _accountDisplayNameController.clear();
    }
    _accountPasswordController.clear();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(registerMode ? '注册账号' : '登录账号'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _accountUsernameController,
                      decoration: const InputDecoration(
                        labelText: '账号',
                        hintText: '输入用户名',
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (registerMode) ...[
                      TextField(
                        controller: _accountDisplayNameController,
                        decoration: const InputDecoration(
                          labelText: '显示名称',
                          hintText: '可选，留空则使用账号名',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _accountPasswordController,
                      obscureText: obscure,
                      decoration: InputDecoration(
                        labelText: '密码',
                        hintText: '至少 6 位',
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => obscure = !obscure),
                          icon: Icon(
                            obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () async {
                    final username = _accountUsernameController.text.trim();
                    final password = _accountPasswordController.text;
                    if (username.isEmpty || password.length < 6) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('请输入账号，并确保密码至少 6 位'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      return;
                    }

                    final auth = context.read<AuthProvider>();
                    final ok = registerMode
                        ? await auth.register(
                            username: username,
                            password: password,
                            displayName:
                                _accountDisplayNameController.text.trim(),
                          )
                        : await auth.login(
                            username: username,
                            password: password,
                          );
                    if (!context.mounted) return;
                    if (ok) {
                      Navigator.pop(dialogContext);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(auth.error ?? '账号操作失败'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  child: Text(registerMode ? '注册并登录' : '登录'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleAccountDeviceTap(String deviceId) async {
    await _applyQuickConnectPeer(deviceId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已带入账号设备，输入密码后即可连接'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleRecentConnectionTap(ConnectionRecord record) async {
    await _applyQuickConnectPeer(record.peerId);
    if (_passwordController.text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('已带入设备ID，请输入密码后继续连接'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }
    await _connectToPeer(record.peerId);
  }

  Future<void> _applyQuickConnectPeer(String peerId) async {
    final connectionProvider = context.read<ConnectionProvider>();
    _deviceIdController.text = peerId;
    if (_passwordController.text.trim().isEmpty) {
      final cachedPassword =
          await connectionProvider.getTrustedPassword(peerId);
      if (cachedPassword != null && cachedPassword.isNotEmpty) {
        _passwordController.text = cachedPassword;
      }
    }
    if (mounted) setState(() {});
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Material(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.04),
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: AppTheme.primaryBlue, size: 22),
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  final String hostname;
  final String platformLabel;
  final bool autoAccept;
  final int trustedCount;

  const _OverviewCard({
    required this.hostname,
    required this.platformLabel,
    required this.autoAccept,
    required this.trustedCount,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF1A2238), Color(0xFF202B45)]
              : const [Color(0xFFF8FBFF), Color(0xFFEEF4FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : AppTheme.primaryBlue.withValues(alpha: 0.10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.shield_moon_outlined,
                  color: AppTheme.primaryBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hostname,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '已准备好发起远程连接；安卓端也可在设置里开启守护模式，尽量保持随时待控。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isDark ? Colors.white70 : AppTheme.textMuted,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoPill(icon: Icons.laptop_mac_rounded, label: platformLabel),
              _InfoPill(
                icon: autoAccept
                    ? Icons.verified_user_rounded
                    : Icons.lock_outline_rounded,
                label: autoAccept ? '自动接受已开启' : '需要手动确认',
                highlight: autoAccept,
              ),
              _InfoPill(
                icon: Icons.devices_other_rounded,
                label: '受信设备 $trustedCount 台',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlight;

  const _InfoPill({
    required this.icon,
    required this.label,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = highlight ? AppTheme.successGreen : AppTheme.primaryBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: baseColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white : AppTheme.textDark,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentConnectionTile extends StatelessWidget {
  final ConnectionRecord record;
  final VoidCallback onTap;

  const _RecentConnectionTile({
    required this.record,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final badgeColor =
        record.isSuccess ? AppTheme.successGreen : AppTheme.errorRed;
    final badgeLabel = record.isSuccess ? '成功' : '失败';

    return Material(
      color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.04),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: AppTheme.brandGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.devices_other_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            record.peerHostname,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            badgeLabel,
                            style: TextStyle(
                              color: badgeColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${record.peerId} · ${record.connectedAt.toString().substring(0, 16)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade500,
                          ),
                    ),
                    if (record.failureReason != null &&
                        record.failureReason!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        record.failureReason!,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppTheme.errorRed),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.arrow_forward_rounded,
                    color: AppTheme.primaryBlue, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountDeviceTile extends StatelessWidget {
  final String hostname;
  final String deviceId;
  final String platform;
  final bool isCurrent;
  final DateTime updatedAt;
  final VoidCallback? onTap;

  const _AccountDeviceTile({
    required this.hostname,
    required this.deviceId,
    required this.platform,
    required this.isCurrent,
    required this.updatedAt,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.04),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.devices_rounded,
                  color: AppTheme.primaryBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hostname,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$deviceId · $platform · ${updatedAt.toString().substring(0, 16)}',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.successGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '本机',
                    style: TextStyle(
                      color: AppTheme.successGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
