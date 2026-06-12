import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../providers/android_host_provider.dart';
import '../utils/theme.dart';

class MobileHostControlPanel extends StatelessWidget {
  final AndroidHostProvider host;
  final bool isDark;
  final VoidCallback onDisconnect;

  const MobileHostControlPanel({
    super.key,
    required this.host,
    required this.isDark,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final stateText = switch (host.state.state) {
      'ready' => host.guardModeEnabled ? '守护模式待命中' : '已授权，待启动推流',
      'running' => host.guardModeEnabled ? '守护模式运行中' : '前台服务运行中',
      'requesting' => '等待录屏授权',
      'error' => '状态异常',
      _ => '未完成初始化',
    };
    final stateColor = host.state.isRunning
        ? AppTheme.successGreen
        : host.state.hasPermission
            ? AppTheme.warningAmber
            : Colors.grey;

    return _PanelSurface(
      isDark: isDark,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusHeader(
              host: host,
              stateText: stateText,
              stateColor: stateColor,
            ),
            const SizedBox(height: 16),
            _GuardModeCard(host: host),
            if (defaultTargetPlatform == TargetPlatform.android) ...[
              const SizedBox(height: 14),
              _AndroidPermissionChecklist(host: host),
            ],
            if (!kIsWeb && Platform.isIOS) ...[
              const SizedBox(height: 14),
              _IosHostNotice(running: host.state.isRunning),
            ],
            if (host.error != null) ...[
              const SizedBox(height: 12),
              _ErrorNotice(message: host.error!),
            ],
            if (host.lanRelayEndpoint != null) ...[
              const SizedBox(height: 14),
              _LanEndpoint(endpoint: host.lanRelayEndpoint!),
            ],
            ..._debugInfoRows(),
            if (host.previewFrame != null) ...[
              const SizedBox(height: 16),
              _PreviewFrame(host: host),
            ],
            const SizedBox(height: 18),
            _ActionRow(host: host, onDisconnect: onDisconnect),
          ],
        ),
      ),
    );
  }

  List<Widget> _debugInfoRows() {
    final items = <MapEntry<String, String?>>[];
    if (host.lastRemoteTap != null) {
      items.add(MapEntry('远程点击', host.lastRemoteTap));
    }
    if (host.lastRemoteAction != null) {
      items.add(MapEntry('远程动作', host.lastRemoteAction));
    }
    if (host.lastRemoteGesture != null) {
      items.add(MapEntry('远程手势', host.lastRemoteGesture));
    }
    if (host.lastRemoteText != null) {
      items.add(MapEntry('远程文本', host.lastRemoteText));
    }
    if (host.lastRemoteClipboard != null) {
      items.add(MapEntry('远程剪贴板', host.lastRemoteClipboard));
    }
    if (items.isEmpty) return const [];

    return [
      const SizedBox(height: 14),
      ...items.map(
        (item) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Text(
                '${item.key}：',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  item.value!,
                  style: const TextStyle(
                    color: AppTheme.primaryBlue,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }
}

class _StatusHeader extends StatelessWidget {
  final AndroidHostProvider host;
  final String stateText;
  final Color stateColor;

  const _StatusHeader({
    required this.host,
    required this.stateText,
    required this.stateColor,
  });

  @override
  Widget build(BuildContext context) {
    final title = !kIsWeb && Platform.isIOS ? 'iOS 被控模式' : '安卓守护模式';
    final subtitle = !kIsWeb && Platform.isIOS
        ? stateText
        : '$stateText · ${host.state.accessibilityEnabled ? "无障碍已开启" : "无障碍未开启"}';

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: stateColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            host.state.isRunning
                ? Icons.cast_connected_rounded
                : host.state.hasPermission
                    ? Icons.verified_user_outlined
                    : Icons.screenshot_monitor_rounded,
            color: stateColor,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: stateColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      subtitle,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: host.busy ? null : host.refresh,
          icon: const Icon(Icons.refresh_rounded, size: 20),
          tooltip: '刷新状态',
        ),
      ],
    );
  }
}

class _GuardModeCard extends StatelessWidget {
  final AndroidHostProvider host;

  const _GuardModeCard({required this.host});

  @override
  Widget build(BuildContext context) {
    final isIos = !kIsWeb && Platform.isIOS;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: host.guardModeEnabled,
            onChanged: host.busy ? null : host.setGuardModeEnabled,
            title: Text(isIos ? '保持 iOS 随时待控' : '保持安卓随时待控'),
            subtitle: Text(
              host.guardModeEnabled
                  ? isIos
                      ? '已启用：进入 App 时会尝试恢复屏幕广播并保持在线。'
                      : '已启用：进入 App 时会尽量自动恢复前台服务并保持在线。'
                  : '关闭后将只保留手动启动的被控端服务。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isIos
                ? 'iOS 使用 ReplayKit 广播扩展录屏。启动被控后需在系统弹窗中确认开始广播。'
                : '一次性完成下面清单后，远端发起连接会更顺畅；录屏授权被系统回收后仍可能需要再次确认。',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AndroidPermissionChecklist extends StatelessWidget {
  final AndroidHostProvider host;

  const _AndroidPermissionChecklist({required this.host});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ChecklistTile(
          label: '录屏权限',
          description: host.state.hasPermission
              ? '已授予；守护模式可直接恢复前台服务。'
              : '首次必须手动确认系统录屏弹窗。',
          done: host.state.hasPermission,
          actionLabel: '去授权',
          onPressed: host.busy ? null : host.requestPermission,
        ),
        const SizedBox(height: 10),
        _ChecklistTile(
          label: '无障碍控制',
          description: host.state.accessibilityEnabled
              ? '已开启；远程点击、返回、拖拽、文本输入可下发到系统界面。'
              : '未开启时只能看屏幕，无法稳定控制系统 UI。',
          done: host.state.accessibilityEnabled,
          actionLabel: '去开启',
          onPressed: host.openAccessibilitySettings,
        ),
        const SizedBox(height: 10),
        _ChecklistTile(
          label: '悬浮窗 / Overlay',
          description: host.state.overlayEnabled
              ? '已允许；便于后续扩展远控提示与状态浮层。'
              : '建议开启，避免后续提示被系统拦截。',
          done: host.state.overlayEnabled,
          actionLabel: '去设置',
          onPressed: host.openOverlaySettings,
        ),
        const SizedBox(height: 10),
        _ChecklistTile(
          label: '通知权限',
          description: host.state.notificationsEnabled
              ? '已允许；前台服务通知更稳定。'
              : '建议开启，否则系统可能限制前台服务可见性。',
          done: host.state.notificationsEnabled,
          actionLabel: '去设置',
          onPressed: host.openNotificationSettings,
        ),
        const SizedBox(height: 10),
        _ChecklistTile(
          label: '忽略电池优化',
          description: host.state.batteryOptimizationIgnored
              ? '已加入白名单；后台驻留更稳定。'
              : '建议改为不受限制，减少系统杀后台。',
          done: host.state.batteryOptimizationIgnored,
          actionLabel: '去设置',
          onPressed: host.openBatteryOptimizationSettings,
        ),
        const SizedBox(height: 10),
        _ChecklistTile(
          label: '厂商自启动 / 后台保护',
          description: host.autostartGuidance,
          done: false,
          actionLabel: '应用详情',
          onPressed: host.openAppDetailsSettings,
        ),
        const SizedBox(height: 12),
        _ReadinessNotice(ready: host.isReadyForRemoteRequests),
      ],
    );
  }
}

class _ReadinessNotice extends StatelessWidget {
  final bool ready;

  const _ReadinessNotice({required this.ready});

  @override
  Widget build(BuildContext context) {
    final color = ready ? AppTheme.successGreen : AppTheme.warningAmber;
    return _InlineNotice(
      color: color,
      icon: ready ? Icons.verified_rounded : Icons.info_outline_rounded,
      text: ready
          ? '主要守护项已就绪。只要录屏权限没有被系统回收，Android 会尽量保持在线并等待连接。'
          : '还有初始化项未完成。建议把清单补齐，降低下次远控失败或被系统回收的概率。',
    );
  }
}

class _IosHostNotice extends StatelessWidget {
  final bool running;

  const _IosHostNotice({required this.running});

  @override
  Widget build(BuildContext context) {
    final color = running ? AppTheme.successGreen : AppTheme.warningAmber;
    return _InlineNotice(
      color: color,
      icon: running ? Icons.verified_rounded : Icons.info_outline_rounded,
      text: running
          ? '屏幕广播运行中。远端设备可实时看到 iPhone 画面。'
          : 'iOS 因系统限制无法远程触控，但可以共享屏幕画面。点击开始被控后在系统弹窗中确认即可。',
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  final String message;

  const _ErrorNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    return _InlineNotice(
      color: AppTheme.errorRed,
      icon: Icons.warning_amber_rounded,
      text: message,
    );
  }
}

class _InlineNotice extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;

  const _InlineNotice({
    required this.color,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color == AppTheme.errorRed ? AppTheme.errorRed : null,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LanEndpoint extends StatelessWidget {
  final String endpoint;

  const _LanEndpoint({required this.endpoint});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.successGreen.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            '局域网：$endpoint/frame.jpg',
            style: const TextStyle(
              color: AppTheme.primaryBlue,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '两端的信令服务器都需设置为 rdesk_server 地址',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _PreviewFrame extends StatelessWidget {
  final AndroidHostProvider host;

  const _PreviewFrame({required this.host});

  @override
  Widget build(BuildContext context) {
    final frame = host.previewFrame!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: frame.width > 0 && frame.height > 0
            ? frame.width / frame.height
            : 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              frame.bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            ),
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.circle, color: Colors.redAccent, size: 8),
                    const SizedBox(width: 6),
                    Text(
                      frame.width > 0 && frame.height > 0
                          ? '实时预览 ${frame.width} x ${frame.height}'
                          : '实时预览',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final AndroidHostProvider host;
  final VoidCallback onDisconnect;

  const _ActionRow({
    required this.host,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _ActionButton(
          icon: Icons.security_rounded,
          label: '申请录屏',
          filled: true,
          onPressed: host.busy ? null : host.requestPermission,
        ),
        _ActionButton(
          icon: Icons.play_arrow_rounded,
          label: host.guardModeEnabled ? '立即进入守护' : '启动服务',
          onPressed:
              host.busy || !host.state.hasPermission ? null : host.startHosting,
        ),
        _ActionButton(
          icon: Icons.stop_rounded,
          label: host.guardModeEnabled ? '暂停守护' : '停止服务',
          onPressed:
              host.busy || !host.state.isRunning ? null : host.stopHosting,
        ),
        _ActionButton(
          icon: Icons.link_off_rounded,
          label: '断开远控',
          color: AppTheme.errorRed,
          onPressed:
              host.busy || !host.canDisconnectViewers ? null : onDisconnect,
        ),
        _ActionButton(
          icon: Icons.accessibility_new_rounded,
          label: '无障碍',
          onPressed: host.openAccessibilitySettings,
        ),
      ],
    );
  }
}

class _ChecklistTile extends StatelessWidget {
  final String label;
  final String description;
  final bool done;
  final String actionLabel;
  final VoidCallback? onPressed;

  const _ChecklistTile({
    required this.label,
    required this.description,
    required this.done,
    required this.actionLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = done ? AppTheme.successGreen : AppTheme.warningAmber;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: onPressed,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final Color? color;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.filled = false,
    this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.primaryBlue;
    if (filled) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 13)),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: onPressed != null ? c : null),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        foregroundColor: c,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(
          color: onPressed != null
              ? c.withValues(alpha: 0.3)
              : Colors.grey.shade300,
        ),
      ),
    );
  }
}

class _PanelSurface extends StatelessWidget {
  final bool isDark;
  final Widget child;

  const _PanelSurface({
    required this.isDark,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.04),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
