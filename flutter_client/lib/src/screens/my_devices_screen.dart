import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../models/connection_info.dart';
import '../providers/auth_provider.dart';
import '../providers/connection_provider.dart';
import '../screens/account_auth_screen.dart';
import '../utils/theme.dart';
import '../widgets/account_auth_dialog.dart';

class MyDevicesScreen extends StatefulWidget {
  const MyDevicesScreen({super.key});

  @override
  State<MyDevicesScreen> createState() => _MyDevicesScreenState();
}

class _MyDevicesScreenState extends State<MyDevicesScreen>
    with SingleTickerProviderStateMixin {
  Timer? _refreshTimer;
  late TabController _tabController;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
    _tabController.dispose();
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
        title: const Text('设备列表'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            onPressed: () => context.read<AuthProvider>().refreshDevices(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
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
              // Tab bar
              TabBar(
                controller: _tabController,
                labelColor: AppTheme.primaryBlue,
                unselectedLabelColor:
                    isDark ? Colors.white54 : AppTheme.textMuted,
                indicatorColor: AppTheme.primaryBlue,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                unselectedLabelStyle:
                    const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                tabs: const [
                  Tab(text: '我的设备'),
                  Tab(text: '最近连接'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: My devices
          _MyDevicesTab(
            searchQuery: _searchQuery,
            isDark: isDark,
            cardBg: cardBg,
            onDeviceTap: (id, hostname, platform, isCurrent) =>
                _navigateToDetail(context,
                    deviceId: id,
                    hostname: hostname,
                    platform: platform,
                    isCurrent: isCurrent),
          ),
          // Tab 2: Recent connections
          _RecentConnectionsTab(
            searchQuery: _searchQuery,
            isDark: isDark,
            cardBg: cardBg,
            onTap: (peerId) {
              final connection = context.read<ConnectionProvider>();
              connection.prepareQuickConnect(peerId);
              context.go('/assist');
            },
          ),
        ],
      ),
    );
  }
}

class _MyDevicesTab extends StatelessWidget {
  final String searchQuery;
  final bool isDark;
  final Color cardBg;
  final void Function(
          String deviceId, String hostname, String platform, bool isCurrent)
      onDeviceTap;

  const _MyDevicesTab({
    required this.searchQuery,
    required this.isDark,
    required this.cardBg,
    required this.onDeviceTap,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final cloudDevices = auth.devices;

        final allDevices = _buildDevices(
          cloudDevices: cloudDevices,
        );

        final filtered = searchQuery.isEmpty
            ? allDevices
            : allDevices.where((d) {
                final q = searchQuery.toLowerCase();
                return d.hostname.toLowerCase().contains(q) ||
                    d.deviceId.contains(q);
              }).toList();

        if (!auth.isLoggedIn) {
          return _EmptyState(
            icon: Icons.cloud_off_rounded,
            title: '登录后可同步设备',
            subtitle: '登录同一个账号后，这里会自动出现你当前在线的其他设备。',
            action: Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => context.push(
                    accountAuthRoute(AccountAuthMode.login, redirect: '/'),
                  ),
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('登录账号'),
                ),
                OutlinedButton(
                  onPressed: () => context.push(
                    accountAuthRoute(AccountAuthMode.register, redirect: '/'),
                  ),
                  child: const Text('注册'),
                ),
              ],
            ),
          );
        }

        if (auth.busy) {
          return const Center(child: CircularProgressIndicator());
        }

        if (filtered.isEmpty) {
          return _EmptyState(
            icon: Icons.devices_rounded,
            title: searchQuery.isEmpty ? '暂无设备' : '未找到匹配设备',
            subtitle:
                searchQuery.isEmpty ? '让其他设备登录同账号并在线后，会显示在这里。' : '尝试使用其他关键词搜索',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final device = filtered[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _DeviceCard(
                device: device,
                isDark: isDark,
                cardBg: cardBg,
                onTap: device.isCurrent
                    ? null
                    : () => onDeviceTap(device.deviceId, device.hostname,
                        device.platform, device.isCurrent),
              ),
            );
          },
        );
      },
    );
  }

  List<_DeviceItem> _buildDevices({
    required List<AccountDevice> cloudDevices,
  }) {
    final items = <_DeviceItem>[];
    for (final item in cloudDevices) {
      items.add(_DeviceItem(
        deviceId: item.deviceId,
        hostname: item.hostname,
        platform: item.platform,
        online: true,
        isCurrent: false,
        updatedAt: item.updatedAt,
      ));
    }
    return items;
  }
}

class _RecentConnectionsTab extends StatelessWidget {
  final String searchQuery;
  final bool isDark;
  final Color cardBg;
  final void Function(String peerId) onTap;

  const _RecentConnectionsTab({
    required this.searchQuery,
    required this.isDark,
    required this.cardBg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionProvider>(
      builder: (context, connection, _) {
        final records = connection.recentConnections;
        final filtered = searchQuery.isEmpty
            ? records
            : records.where((r) {
                final q = searchQuery.toLowerCase();
                return r.peerId.contains(q) ||
                    r.peerHostname.toLowerCase().contains(q);
              }).toList();

        if (filtered.isEmpty) {
          return _EmptyState(
            icon: Icons.history_rounded,
            title: searchQuery.isEmpty ? '暂无连接记录' : '未找到匹配记录',
            subtitle: searchQuery.isEmpty ? '连接过的设备会自动显示在这里' : '尝试使用其他关键词搜索',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final record = filtered[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RecentCard(
                record: record,
                isDark: isDark,
                cardBg: cardBg,
                onTap: () => onTap(record.peerId),
              ),
            );
          },
        );
      },
    );
  }
}

class _DeviceItem {
  final String deviceId;
  final String hostname;
  final String platform;
  final bool online;
  final bool isCurrent;
  final DateTime updatedAt;

  const _DeviceItem({
    required this.deviceId,
    required this.hostname,
    required this.platform,
    required this.online,
    required this.isCurrent,
    required this.updatedAt,
  });
}

class _DeviceCard extends StatelessWidget {
  final _DeviceItem device;
  final bool isDark;
  final Color cardBg;
  final VoidCallback? onTap;

  const _DeviceCard({
    required this.device,
    required this.isDark,
    required this.cardBg,
    required this.onTap,
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
            border: device.isCurrent
                ? Border.all(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                    width: 1.5)
                : Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.04)),
          ),
          child: Row(
            children: [
              // Platform icon with gradient cover
              _DeviceCover(
                platform: device.platform,
                online: device.online,
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
                            device.hostname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (device.isCurrent)
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
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          _platformIcon(device.platform),
                          size: 14,
                          color: AppTheme.primaryBlue,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${device.platform} · ${device.deviceId}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  isDark ? Colors.white54 : AppTheme.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '最近在线 ${_formatTime(device.updatedAt)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              if (!device.isCurrent)
                const Icon(Icons.chevron_right_rounded,
                    color: Colors.grey, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _platformIcon(String platform) {
    final n = platform.toLowerCase();
    if (n.contains('android')) return Icons.android_rounded;
    if (n.contains('ios') || n.contains('iphone')) {
      return Icons.phone_iphone_rounded;
    }
    if (n.contains('mac')) return Icons.laptop_mac_rounded;
    if (n.contains('windows')) return Icons.window_rounded;
    return Icons.devices_other_rounded;
  }

  static String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }
}

class _DeviceCover extends StatelessWidget {
  final String platform;
  final bool online;

  const _DeviceCover({required this.platform, required this.online});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: _coverColors(platform),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Icon(
              _DeviceCard._platformIcon(platform),
              size: 28,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: online ? AppTheme.successGreen : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static List<Color> _coverColors(String platform) {
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

class _RecentCard extends StatelessWidget {
  final ConnectionRecord record;
  final bool isDark;
  final Color cardBg;
  final VoidCallback onTap;

  const _RecentCard({
    required this.record,
    required this.isDark,
    required this.cardBg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor =
        record.isSuccess ? AppTheme.successGreen : AppTheme.errorRed;
    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.devices_other_rounded,
                    color: AppTheme.primaryBlue, size: 20),
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
                            record.peerHostname,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            record.isSuccess ? '成功' : '失败',
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${record.peerId} · ${record.peerOs}',
                      style: TextStyle(
                        color: isDark ? Colors.white54 : AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded,
                  size: 16,
                  color: isDark ? Colors.white38 : AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 48, color: AppTheme.primaryBlue.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white54
                    : AppTheme.textMuted,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
