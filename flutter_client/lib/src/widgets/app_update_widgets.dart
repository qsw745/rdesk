import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/app_update_provider.dart';
import '../providers/session_provider.dart';

class UpdateLifecycle extends StatefulWidget {
  final Widget child;
  const UpdateLifecycle({super.key, required this.child});
  @override
  State<UpdateLifecycle> createState() => _UpdateLifecycleState();
}

class _UpdateLifecycleState extends State<UpdateLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(context.read<AppUpdateProvider>().check());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(context.read<AppUpdateProvider>().check());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});
  @override
  Widget build(BuildContext context) =>
      Consumer<AppUpdateProvider>(builder: (context, update, _) {
        if (!update.showBanner) return const SizedBox.shrink();
        return SafeArea(
            bottom: false,
            child: Material(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        children: [
                          Text('RDesk ${update.release!.version} 可更新'),
                          TextButton(
                              onPressed: () =>
                                  context.go('/settings?section=about'),
                              child: const Text('查看更新')),
                          TextButton(
                              onPressed: update.ignore,
                              child: const Text('忽略此版本')),
                        ]))));
      });
}

class UpdateCard extends StatelessWidget {
  const UpdateCard({super.key});
  Future<void> _install(BuildContext context, AppUpdateProvider update) async {
    final session = context.read<SessionProvider>();
    if (session.currentSession != null) {
      await update.install(sessionActive: true);
      return;
    }
    final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(update.release!.isStore ? '前往 App Store' : '安装更新'),
              content: Text(update.release!.isStore
                  ? '将在 App Store 中完成更新。'
                  : '安装可能需要关闭 RDesk，并中断正在进行的屏幕共享。请先保存工作，按系统提示完成安装。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('稍后')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('继续'))
              ],
            ));
    if (proceed == true && context.mounted) {
      await update.install(sessionActive: session.currentSession != null);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Consumer<AppUpdateProvider>(builder: (context, update, _) {
        final release = update.release;
        return Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text('应用更新',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w600)),
                            OutlinedButton.icon(
                                onPressed: update.busy
                                    ? null
                                    : () => update.check(manual: true),
                                icon: const Icon(Icons.refresh),
                                label: Text(update.phase == UpdatePhase.checking
                                    ? '正在检查…'
                                    : '检查更新')),
                          ]),
                      SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('自动检查更新'),
                          subtitle: const Text('启动和回到前台时检查，有新版会在主界面提醒'),
                          value: update.automatic,
                          onChanged: update.setAutomatic),
                      if (update.message != null)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(update.message!)),
                      if (release != null) ...[
                        Text(
                            '可用版本 ${release.version}${release.version.build != null ? ' (${release.version.build})' : ''}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        for (final note in release.notes)
                          Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('• $note')),
                        const SizedBox(height: 12),
                        if (update.phase == UpdatePhase.downloading) ...[
                          LinearProgressIndicator(value: update.progress),
                          const SizedBox(height: 8),
                          Text(
                              '已下载 ${(update.received / 1048576).toStringAsFixed(1)} / ${(release.bytes! / 1048576).toStringAsFixed(1)} MB'),
                          TextButton(
                              onPressed: update.cancelDownload,
                              child: const Text('取消下载')),
                        ] else
                          Wrap(spacing: 12, runSpacing: 8, children: [
                            if (!release.isStore)
                              OutlinedButton(
                                  onPressed:
                                      update.busy ? null : update.download,
                                  child: Text(update.package == null
                                      ? '下载更新'
                                      : '重新下载')),
                            if (release.isStore || update.package != null)
                              FilledButton(
                                  onPressed: update.busy
                                      ? null
                                      : () => _install(context, update),
                                  child: Text(release.isStore
                                      ? '前往 App Store 更新'
                                      : '安装更新')),
                            if (update.installPermissionRequired)
                              OutlinedButton(
                                  onPressed: update.openInstallSettings,
                                  child: const Text('允许安装应用')),
                          ]),
                      ],
                    ])));
      });
}
