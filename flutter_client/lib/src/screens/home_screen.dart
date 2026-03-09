import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/connection_info.dart';
import '../models/session.dart';
import '../providers/connection_provider.dart';
import '../providers/session_provider.dart';
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
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    context.read<ConnectionProvider>().initialize();
  }

  @override
  void dispose() {
    _deviceIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final deviceId = _deviceIdController.text.trim();
    final password = _passwordController.text.trim();

    if (deviceId.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请输入设备ID和连接密码'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    final provider = context.read<ConnectionProvider>();
    final sessionId = await provider.connect(deviceId, password);
    if (sessionId != null && mounted) {
      context.read<SessionProvider>().setSession(
            SessionInfo(
              sessionId: sessionId,
              peerId: deviceId,
              peerHostname: '远程设备 $deviceId',
              peerOs: '未知系统',
              state: SessionState.active,
              connectedAt: DateTime.now(),
              latencyMs: 42,
            ),
          );
      context.go('/remote/$sessionId');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.connected_tv, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RDesk 远程桌面',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '安全、高效的跨平台远程控制',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                    const Spacer(),
                    FilledButton.tonalIcon(
                      onPressed: () => context.go('/settings'),
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('设置'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.14),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 540),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Consumer<ConnectionProvider>(
                        builder: (context, provider, _) {
                          return DeviceIdDisplay(
                            deviceId: provider.localDevice?.deviceId ?? '000000000',
                            temporaryPassword: provider.temporaryPassword,
                            onRefreshPassword: provider.refreshPassword,
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.link, color: AppTheme.primaryBlue, size: 22),
                                const SizedBox(width: 10),
                                Text(
                                  '连接远程设备',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _deviceIdController,
                              decoration: const InputDecoration(
                                labelText: '设备ID',
                                hintText: '请输入对方9位设备ID',
                                prefixIcon: Icon(Icons.devices),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(9),
                              ],
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _passwordController,
                              decoration: InputDecoration(
                                labelText: '连接密码',
                                hintText: '请输入连接密码',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _showPassword ? Icons.visibility_off : Icons.visibility,
                                  ),
                                  onPressed: () =>
                                      setState(() => _showPassword = !_showPassword),
                                ),
                              ),
                              obscureText: !_showPassword,
                            ),
                            const SizedBox(height: 20),
                            Consumer<ConnectionProvider>(
                              builder: (context, provider, _) {
                                final isConnecting =
                                    provider.connectionState == SessionState.connecting;
                                return Container(
                                  height: 54,
                                  decoration: BoxDecoration(
                                    gradient: isConnecting ? null : AppTheme.brandGradient,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: ElevatedButton(
                                    onPressed: isConnecting ? null : _connect,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      disabledBackgroundColor: Colors.grey.shade300,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: isConnecting
                                        ? const Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2.4,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              SizedBox(width: 12),
                                              Text(
                                                '连接中...',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          )
                                        : const Text(
                                            '连接',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
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
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.error_outline, color: Colors.red),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            provider.errorMessage!,
                                            style: const TextStyle(color: Colors.red),
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
                      const SizedBox(height: 22),
                      Consumer<ConnectionProvider>(
                        builder: (context, provider, _) {
                          final records = provider.recentConnections.take(3).toList();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '最近连接',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              if (records.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).cardColor,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: const Text('暂无最近连接，连接成功后会自动记录。'),
                                )
                              else
                                Column(
                                  children: records.map((record) {
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: _RecentConnectionTile(
                                        record: record,
                                        onTap: () => _deviceIdController.text = record.peerId,
                                      ),
                                    );
                                  }).toList(),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          _QuickAction(
                            icon: Icons.history,
                            label: '连接历史',
                            onTap: () => context.go('/logs'),
                          ),
                          const SizedBox(width: 12),
                          _QuickAction(
                            icon: Icons.folder_outlined,
                            label: '文件管理',
                            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('连接成功后可进入文件管理')),
                            ),
                          ),
                          const SizedBox(width: 12),
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
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _BottomDockButton(
                  icon: Icons.home_rounded,
                  label: '首页',
                  active: true,
                  onTap: () {},
                ),
                _BottomDockButton(
                  icon: Icons.history_toggle_off_rounded,
                  label: '历史',
                  onTap: () => context.go('/logs'),
                ),
                _BottomDockButton(
                  icon: Icons.settings_rounded,
                  label: '设置',
                  onTap: () => context.go('/settings'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(icon, color: AppTheme.primaryBlue, size: 26),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
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
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: AppTheme.brandGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.devices_other, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(record.peerHostname, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      '${record.peerId} • ${record.connectedAt.toString().substring(0, 16)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: onTap,
                child: const Text('填入'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomDockButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  const _BottomDockButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        active ? AppTheme.primaryBlue : Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
