import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import '../utils/theme.dart';

class ConnectionLogScreen extends StatelessWidget {
  const ConnectionLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('连接历史'),
        automaticallyImplyLeading: false,
      ),
      body: Consumer<ConnectionProvider>(
        builder: (context, provider, _) {
          final records = provider.recentConnections;

          if (records.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.history_rounded,
                      size: 48,
                      color: AppTheme.primaryBlue.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '暂无连接历史',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '成功或失败的连接都会记录在这里',
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            );
          }

          // Stats
          final successCount =
              records.where((r) => r.isSuccess).length;
          final failCount = records.length - successCount;

          return Column(
            children: [
              // Stats bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    _StatChip(
                      icon: Icons.check_circle_outline_rounded,
                      label: '成功 $successCount',
                      color: AppTheme.successGreen,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 10),
                    _StatChip(
                      icon: Icons.cancel_outlined,
                      label: '失败 $failCount',
                      color: AppTheme.errorRed,
                      isDark: isDark,
                    ),
                    const Spacer(),
                    Text(
                      '共 ${records.length} 条',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              // List
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: records.length,
                  itemBuilder: (context, index) {
                    final record = records[index];
                    final isSuccess = record.isSuccess;
                    final statusColor = isSuccess
                        ? AppTheme.successGreen
                        : AppTheme.errorRed;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: isDark
                            ? const Color(0xFF1E1E2E)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () {
                            context
                                .read<ConnectionProvider>()
                                .prepareQuickConnect(record.peerId);
                            context.go('/');
                          },
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
                                    color: statusColor
                                        .withValues(alpha: 0.1),
                                    borderRadius:
                                        BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    record.connectionType == 'p2p'
                                        ? Icons.link_rounded
                                        : Icons.cloud_outlined,
                                    color: statusColor,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                            ),
                                          ),
                                          Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3),
                                            decoration: BoxDecoration(
                                              color: statusColor
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              isSuccess ? '成功' : '失败',
                                              style: TextStyle(
                                                color: statusColor,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${record.peerId} · ${record.peerOs} · ${record.connectedAt.toString().substring(0, 16)}',
                                        style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 12,
                                        ),
                                      ),
                                      if (record.failureReason != null &&
                                          record
                                              .failureReason!.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          record.failureReason!,
                                          style: TextStyle(
                                            color: AppTheme.errorRed,
                                            fontSize: 12,
                                          ),
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
                                    color: AppTheme.primaryBlue
                                        .withValues(alpha: 0.08),
                                    borderRadius:
                                        BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.replay_rounded,
                                    color: AppTheme.primaryBlue,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
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
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
