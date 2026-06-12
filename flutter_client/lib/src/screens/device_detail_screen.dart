import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/session.dart';
import '../providers/connection_provider.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/theme.dart';

class DeviceDetailScreen extends StatefulWidget {
  final String deviceId;
  final String hostname;
  final String platform;

  const DeviceDetailScreen({
    super.key,
    required this.deviceId,
    required this.hostname,
    required this.platform,
  });

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  bool _connecting = false;

  Future<void> _connectRemote() async {
    setState(() => _connecting = true);
    try {
      final connection = context.read<ConnectionProvider>();
      final settings = context.read<SettingsProvider>();
      final sessionProvider = context.read<SessionProvider>();

      // Try same-account passwordless connect first (server handles auth)
      final sessionId = await connection.connect(widget.deviceId, '');
      if (!mounted) return;
      if (sessionId != null) {
        await settings.refreshTrustedPeers();
        if (!mounted) return;
        sessionProvider.setSession(
          SessionInfo(
            sessionId: sessionId,
            peerId: widget.deviceId,
            peerHostname: widget.hostname,
            peerOs: widget.platform,
            state: SessionState.active,
            connectedAt: DateTime.now(),
          ),
          accessPassword: '',
        );
        context.go('/remote/$sessionId');
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _connecting = false);
    _handleConnectFailure();
  }

  Future<void> _connectFileTransfer() async {
    setState(() => _connecting = true);
    try {
      final connection = context.read<ConnectionProvider>();
      final settings = context.read<SettingsProvider>();
      final sessionProvider = context.read<SessionProvider>();

      final sessionId = await connection.connect(widget.deviceId, '');
      if (!mounted) return;
      if (sessionId != null) {
        await settings.refreshTrustedPeers();
        if (!mounted) return;
        sessionProvider.setSession(
          SessionInfo(
            sessionId: sessionId,
            peerId: widget.deviceId,
            peerHostname: widget.hostname,
            peerOs: widget.platform,
            state: SessionState.active,
            connectedAt: DateTime.now(),
          ),
          accessPassword: '',
        );
        context.go('/files/$sessionId');
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _connecting = false);
    _handleConnectFailure();
  }

  void _handleConnectFailure() {
    final connection = context.read<ConnectionProvider>();
    final message = connection.errorMessage ?? '连接失败，请稍后重试';
    final needsPassword =
        message.contains('连接密码错误') || message.contains('需要验证码');
    if (needsPassword) {
      connection.prepareQuickConnect(widget.deviceId);
      context.go('/assist');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('需要验证码才能连接此设备')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final surfaceBg =
        isDark ? const Color(0xFF121218) : const Color(0xFFF5F7FA);

    return Scaffold(
      backgroundColor: surfaceBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.successGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 8, color: AppTheme.successGreen),
                  SizedBox(width: 5),
                  Text('在线',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.successGreen,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                widget.hostname,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded),
            onPressed: () => _showMoreMenu(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
        children: [
          // Preview card with "进入桌面" button
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Desktop preview area
                Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _platformGradient(widget.platform),
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Decorative circles
                      Positioned(
                        left: -20,
                        top: -20,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Positioned(
                        right: -10,
                        bottom: -30,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      // Platform icon
                      Positioned(
                        right: 24,
                        bottom: 20,
                        child: Icon(
                          _platformIcon(widget.platform),
                          size: 56,
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
                      // "点击进入桌面" button
                      Center(
                        child: _connecting
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : GestureDetector(
                                onTap: _connectRemote,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.15),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.touch_app_rounded,
                                          size: 20,
                                          color: _platformGradient(
                                              widget.platform)[1]),
                                      const SizedBox(width: 8),
                                      Text(
                                        '点击进入桌面',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: _platformGradient(
                                              widget.platform)[1],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),

                // Quick action buttons row
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Row(
                    children: [
                      _ActionButton(
                        icon: Icons.folder_open_rounded,
                        label: '文件传输',
                        color: AppTheme.primaryBlue,
                        onTap: _connecting ? null : _connectFileTransfer,
                      ),
                      const SizedBox(width: 12),
                      _ActionButton(
                        icon: Icons.visibility_rounded,
                        label: '观看模式',
                        color: const Color(0xFF6C5CE7),
                        onTap: _connecting ? null : _connectRemote,
                      ),
                      const SizedBox(width: 12),
                      _ActionButton(
                        icon: Icons.camera_alt_rounded,
                        label: '摄像头',
                        color: const Color(0xFF2BBFA0),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('摄像头功能即将推出')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Remote control actions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                _SmallAction(
                  icon: Icons.lock_outline_rounded,
                  label: '锁屏',
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('锁屏功能即将推出')),
                  ),
                ),
                _SmallAction(
                  icon: Icons.refresh_rounded,
                  label: '重启',
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('重启功能即将推出')),
                  ),
                ),
                _SmallAction(
                  icon: Icons.power_settings_new_rounded,
                  label: '关机',
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('关机功能即将推出')),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Device info card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '设备信息',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                _InfoRow(label: '设备名称', value: widget.hostname, isDark: isDark),
                _InfoRow(
                    label: '设备 ID', value: widget.deviceId, isDark: isDark),
                _InfoRow(label: '系统平台', value: widget.platform, isDark: isDark),
                _InfoRow(label: '状态', value: '在线', isDark: isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMoreMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: const Text('重命名设备'),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('重命名功能即将推出')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('设备详情'),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _platformIcon(String platform) {
    final n = platform.toLowerCase();
    if (n.contains('mac')) return Icons.laptop_mac_rounded;
    if (n.contains('windows')) return Icons.window_rounded;
    if (n.contains('ios') || n.contains('iphone')) {
      return Icons.phone_iphone_rounded;
    }
    if (n.contains('android')) return Icons.phone_android_rounded;
    return Icons.devices_other_rounded;
  }

  static List<Color> _platformGradient(String platform) {
    final n = platform.toLowerCase();
    if (n.contains('mac') || n.contains('ios')) {
      return const [Color(0xFF7FC4FF), Color(0xFF2258D6)];
    }
    if (n.contains('windows')) {
      return const [Color(0xFFB9D4E8), Color(0xFF5E97DD)];
    }
    if (n.contains('android')) {
      return const [Color(0xFF72D680), Color(0xFF0B8B65)];
    }
    return const [Color(0xFF9EC6E5), Color(0xFF6AA4D8)];
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white70
                    : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SmallAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18, color: isDark ? Colors.white54 : AppTheme.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : AppTheme.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
