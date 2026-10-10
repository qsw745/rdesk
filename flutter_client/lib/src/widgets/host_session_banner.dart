import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/desktop_host_provider.dart';
import '../ui/components.dart';
import '../ui/tokens.dart';

/// Tells the person at this computer, on every page, that it is being
/// viewed or operated remotely, by whom and for how long, and lets them end
/// it. Takes no space while nobody is connected.
class HostSessionBanner extends StatelessWidget {
  const HostSessionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final host = context.watch<DesktopHostProvider>();
    final since = host.remoteAccessSince;
    if (!host.remoteAccessActive || since == null) {
      return const SizedBox.shrink();
    }
    return _ActiveBanner(
      since: since,
      viewers: host.currentViewers,
      onDisconnect: host.revokeAccessAndDisconnect,
    );
  }
}

class _ActiveBanner extends StatefulWidget {
  const _ActiveBanner({
    required this.since,
    required this.viewers,
    required this.onDisconnect,
  });

  final DateTime since;
  final List<HostViewerInfo> viewers;
  final Future<bool> Function() onDisconnect;

  @override
  State<_ActiveBanner> createState() => _ActiveBannerState();
}

class _ActiveBannerState extends State<_ActiveBanner> {
  late final Timer _ticker = Timer.periodic(
      const Duration(seconds: 1), (_) => setState(() {}));
  bool _disconnecting = false;

  @override
  void initState() {
    super.initState();
    _ticker; // start counting
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  static String _clock(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  Future<void> _disconnect() async {
    setState(() => _disconnecting = true);
    try {
      await widget.onDisconnect();
    } finally {
      if (mounted) setState(() => _disconnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = RdPalette.of(context);
    final t = Theme.of(context).textTheme;
    const onBrand = Colors.white;
    final elapsed = DateTime.now().difference(widget.since);
    final viewers = widget.viewers;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        color: p.brand,
        padding: const EdgeInsets.symmetric(
            horizontal: Rd.pagePaddingDesktop, vertical: Rd.s16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: Rd.s16,
                        children: [
                          Text('本机被控中',
                              style:
                                  t.titleLarge!.copyWith(color: onBrand)),
                          Text(_clock(elapsed),
                              style: t.titleLarge!.copyWith(
                                  color: onBrand,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ])),
                        ]),
                    const SizedBox(height: Rd.s4),
                    Text(
                        viewers.isEmpty
                            ? '有设备正在访问此电脑'
                            : '当前有 ${viewers.length} 台设备正在控制此电脑',
                        style: t.bodySmall!
                            .copyWith(color: onBrand.withValues(alpha: 0.9))),
                  ]),
            ),
            const SizedBox(width: Rd.s16),
            OutlinedButton(
              onPressed: _disconnecting ? null : _disconnect,
              style: OutlinedButton.styleFrom(
                  backgroundColor: onBrand,
                  foregroundColor: p.brand,
                  disabledBackgroundColor: onBrand.withValues(alpha: 0.7),
                  side: BorderSide.none),
              child: Text(_disconnecting ? '正在断开…' : '断开所有远控'),
            ),
          ]),
          if (viewers.isNotEmpty) ...[
            const SizedBox(height: Rd.s12),
            Wrap(spacing: Rd.s8, runSpacing: Rd.s8, children: [
              for (final viewer in viewers)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Rd.s12, vertical: 6),
                  decoration: BoxDecoration(
                      color: onBrand.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(Rd.radiusSm)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(rdPlatformOf(viewer.platform).icon,
                        size: 16, color: onBrand),
                    const SizedBox(width: Rd.s8),
                    Text(viewer.name,
                        style: t.labelLarge!.copyWith(color: onBrand)),
                    const SizedBox(width: Rd.s8),
                    Text(
                        '已连接 ${_clock(DateTime.now().difference(viewer.since))}',
                        style: t.labelSmall!.copyWith(
                            color: onBrand.withValues(alpha: 0.85),
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                  ]),
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}
