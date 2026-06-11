import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/connection_provider.dart';
import '../utils/theme.dart';
import '../widgets/account_auth_dialog.dart';

class CloudDevicesScreen extends StatefulWidget {
  const CloudDevicesScreen({super.key});

  @override
  State<CloudDevicesScreen> createState() => _CloudDevicesScreenState();
}

class _CloudDevicesScreenState extends State<CloudDevicesScreen> {
  Timer? _refreshTimer;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) {
        if (mounted) {
          final auth = context.read<AuthProvider>();
          if (auth.isLoggedIn && !auth.busy) {
            auth.refreshDevices(notifyOnStart: false);
          }
        }
      },
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _navigateToDetail(
    BuildContext context, {
    required String deviceId,
    required String hostname,
    required String platform,
    required bool isCurrent,
  }) {
    if (isCurrent) return;
    context.push(
      '/device-detail/$deviceId',
      extra: {'hostname': hostname, 'platform': platform},
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    return Scaffold(
      appBar: AppBar(
        title: const Text('云设备'),
        automaticallyImplyLeading: false,
        actions: [
          Consumer<AuthProvider>(
            builder: (context, auth, _) {
              if (!auth.isLoggedIn) return const SizedBox.shrink();
              return IconButton(
                onPressed: auth.busy ? null : auth.refreshDevices,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: '刷新',
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Consumer2<AuthProvider, ConnectionProvider>(
        builder: (context, auth, connection, _) {
          if (!auth.isLoggedIn) {
            return _buildLoginPrompt(context, isDark, cardBg);
          }

          final currentId = connection.localDevice?.deviceId;
          final devices = auth.devices
              .where((item) => item.deviceId != currentId)
              .toList();

          final filtered = _searchQuery.isEmpty
              ? devices
              : devices.where((d) {
                  final q = _searchQuery.toLowerCase();
                  return d.hostname.toLowerCase().contains(q) ||
                      d.deviceId.contains(q);
                }).toList();

          return Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  decoration: InputDecoration(
                    hintText: '搜索设备名称或ID',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFF3F5F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),

              // Account header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        gradient: AppTheme.brandGradient,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person_rounded,
                          color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        auth.session!.displayName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                    Text(
                      '${filtered.length} 台在线',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),

              if (auth.error != null && auth.error!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.errorRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: AppTheme.errorRed, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(auth.error!,
                              style: const TextStyle(
                                  color: AppTheme.errorRed, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ),

              // Device list
              Expanded(
                child: auth.busy
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                        ? _buildEmptyState(context, isDark)
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _CloudDeviceCard(
                                  cardBg: cardBg,
                                  isDark: isDark,
                                  hostname: item.hostname,
                                  deviceId: item.deviceId,
                                  platform: item.platform,
                                  isCurrent: false,
                                  onTap: () => _navigateToDetail(
                                    context,
                                    deviceId: item.deviceId,
                                    hostname: item.hostname,
                                    platform: item.platform,
                                    isCurrent: false,
                                  ),
                                  onConnect: () => _navigateToDetail(
                                    context,
                                    deviceId: item.deviceId,
                                    hostname: item.hostname,
                                    platform: item.platform,
                                    isCurrent: false,
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLoginPrompt(BuildContext context, bool isDark, Color cardBg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_rounded,
                  size: 48, color: AppTheme.primaryBlue),
            ),
            const SizedBox(height: 20),
            const Text(
              '登录云设备',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              '登录同一个账号后，可查看该账号下\n当前在线的所有设备并快速发起远程协助',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white54 : AppTheme.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 130,
                  height: 44,
                  child: OutlinedButton(
                    onPressed: () =>
                        showAccountAuthDialog(context, registerMode: false),
                    child: const Text('登录'),
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 130,
                  height: 44,
                  child: FilledButton(
                    onPressed: () =>
                        showAccountAuthDialog(context, registerMode: true),
                    child: const Text('注册'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.devices_rounded,
                  size: 40, color: AppTheme.primaryBlue),
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty ? '未找到匹配设备' : '暂无在线设备',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? '尝试使用其他关键词搜索'
                  : '在其他设备上登录同一账号后，\n设备会自动出现在这里',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : AppTheme.textMuted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloudDeviceCard extends StatelessWidget {
  final Color cardBg;
  final bool isDark;
  final String hostname;
  final String deviceId;
  final String platform;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback? onConnect;

  const _CloudDeviceCard({
    required this.cardBg,
    required this.isDark,
    required this.hostname,
    required this.deviceId,
    required this.platform,
    required this.isCurrent,
    required this.onTap,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: isCurrent
                ? Border.all(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.25),
                    width: 1.5)
                : Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.04)),
          ),
          child: Row(
            children: [
              // Platform icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: _platformColors(platform),
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Icon(
                        _platformIcon(platform),
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppTheme.successGreen,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            hostname,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCurrent)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color:
                                  AppTheme.primaryBlue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '本机',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppTheme.primaryBlue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$platform · $deviceId',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isCurrent) ...[
                const SizedBox(width: 8),
                SizedBox(
                  height: 34,
                  child: FilledButton.icon(
                    onPressed: onConnect,
                    icon: const Icon(Icons.play_arrow_rounded, size: 16),
                    label: const Text('连接', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
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

  static List<Color> _platformColors(String platform) {
    final n = platform.toLowerCase();
    if (n.contains('mac') || n.contains('ios')) {
      return const [Color(0xFF6CB6FF), Color(0xFF2258D6)];
    }
    if (n.contains('windows')) {
      return const [Color(0xFFB9D4E8), Color(0xFF5E97DD)];
    }
    if (n.contains('android')) {
      return const [Color(0xFF62C870), Color(0xFF0B8B65)];
    }
    return const [Color(0xFF9EC6E5), Color(0xFF6AA4D8)];
  }
}
