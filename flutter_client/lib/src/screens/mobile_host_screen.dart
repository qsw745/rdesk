import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/android_host_provider.dart';
import '../utils/theme.dart';
import '../widgets/mobile_host_control_panel.dart';

class MobileHostScreen extends StatelessWidget {
  const MobileHostScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final supported = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android || Platform.isIOS);

    return Scaffold(
      appBar: AppBar(
        title: Text(Platform.isIOS ? 'iOS 被控' : '移动被控'),
      ),
      body: SafeArea(
        child: supported
            ? Consumer<AndroidHostProvider>(
                builder: (context, host, _) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      _MobileHostSummary(host: host),
                      const SizedBox(height: 14),
                      MobileHostControlPanel(
                        host: host,
                        isDark: isDark,
                        onDisconnect: () =>
                            _confirmDisconnectViewers(context, host),
                      ),
                    ],
                  );
                },
              )
            : const _UnsupportedMobileHost(),
      ),
    );
  }

  void _confirmDisconnectViewers(
    BuildContext context,
    AndroidHostProvider host,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('断开远控连接'),
        content: const Text('确定要断开当前所有远程查看端的连接吗？\n断开后对方需要重新输入密码才能连接。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await host.disconnectCurrentViewer();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok ? '已断开所有远控连接并刷新密钥' : '断开操作部分完成，请检查连接状态'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
            child: const Text('断开'),
          ),
        ],
      ),
    );
  }
}

class _MobileHostSummary extends StatelessWidget {
  final AndroidHostProvider host;

  const _MobileHostSummary({required this.host});

  @override
  Widget build(BuildContext context) {
    final running = host.state.isRunning;
    final color = running
        ? AppTheme.successGreen
        : host.state.hasPermission
            ? AppTheme.warningAmber
            : Colors.grey;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: Theme.of(context).brightness == Brightness.dark
              ? const [Color(0xFF1C2440), Color(0xFF151B2D)]
              : const [Color(0xFFF7FAFF), Color(0xFFEFF4FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primaryBlue.withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.phone_android_rounded, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Platform.isIOS ? 'iOS 屏幕共享' : 'Android 被控端',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  running ? '服务运行中，可以接受远端查看请求。' : '完成授权后即可把这台手机作为被控端。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textMuted,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UnsupportedMobileHost extends StatelessWidget {
  const _UnsupportedMobileHost();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.phone_android_rounded,
              size: 48,
              color: AppTheme.primaryBlue.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 16),
            const Text(
              '当前平台不支持移动被控',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              '请在 Android 或 iOS 客户端中使用该入口。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
