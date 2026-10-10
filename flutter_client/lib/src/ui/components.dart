import 'package:flutter/material.dart';
import 'tokens.dart';

enum RdTone { neutral, brand, online, warning, danger, power }

extension RdToneColors on RdTone {
  Color fg(RdPalette p) => switch (this) {
        RdTone.neutral => p.inkSecondary,
        RdTone.brand => p.brand,
        RdTone.online => p.online,
        RdTone.warning => p.warning,
        RdTone.danger => p.danger,
        RdTone.power => p.power,
      };
  Color bg(RdPalette p) => switch (this) {
        RdTone.neutral => p.surfaceMuted,
        RdTone.brand => p.brandSoft,
        RdTone.online => p.onlineSoft,
        RdTone.warning => p.warningSoft,
        RdTone.danger => p.dangerSoft,
        RdTone.power => p.powerSoft,
      };
}

/// White surface with a hairline border. Tappable when [onTap] is set.
class RdCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;
  const RdCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(Rd.s16),
      this.onTap,
      this.color,
      this.radius = Rd.radius});

  @override
  Widget build(BuildContext context) {
    final p = RdPalette.of(context);
    final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: p.border));
    return Material(
      color: color ?? p.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// Small uppercase-free section label with optional trailing action.
class RdSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  const RdSectionHeader(this.title,
      {super.key,
      this.trailing,
      this.padding = const EdgeInsets.fromLTRB(4, 0, 4, 10)});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: padding,
      child: Row(children: [
        Expanded(
            child: Text(title,
                style: t.labelMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: RdPalette.of(context).inkSecondary))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Inset grouped list: rows separated by indented hairlines.
class RdGroup extends StatelessWidget {
  final List<Widget> children;
  const RdGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final p = RdPalette.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(height: 1, indent: 56, color: p.divider));
      }
      rows.add(children[i]);
    }
    return RdCard(padding: EdgeInsets.zero, child: Column(children: rows));
  }
}

/// Row for [RdGroup]: tinted icon, title, optional subtitle and trailing.
class RdTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final RdTone tone;
  final bool chevron;
  const RdTile(
      {super.key,
      required this.icon,
      required this.title,
      this.subtitle,
      this.trailing,
      this.onTap,
      this.tone = RdTone.brand,
      this.chevron = true});

  @override
  Widget build(BuildContext context) {
    final p = RdPalette.of(context);
    final t = Theme.of(context).textTheme;
    final danger = tone == RdTone.danger;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            RdIconBadge(icon: icon, tone: tone, size: 30),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Text(title,
                      style: t.bodyLarge!.copyWith(
                          fontWeight: FontWeight.w500,
                          color: danger ? p.danger : p.ink)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: t.bodySmall),
                  ],
                ])),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            if (onTap != null && chevron && trailing == null)
              Icon(Icons.chevron_right_rounded, color: p.inkTertiary, size: 20),
          ]),
        ),
      ),
    );
  }
}

/// Icon inside a softly tinted rounded square.
class RdIconBadge extends StatelessWidget {
  final IconData icon;
  final RdTone tone;
  final double size;
  const RdIconBadge(
      {super.key,
      required this.icon,
      this.tone = RdTone.brand,
      this.size = 36});

  @override
  Widget build(BuildContext context) {
    final p = RdPalette.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: tone.bg(p), borderRadius: BorderRadius.circular(size * 0.28)),
      child: Icon(icon, size: size * 0.56, color: tone.fg(p)),
    );
  }
}

class RdStatusDot extends StatelessWidget {
  final Color color;
  final double size;
  const RdStatusDot({super.key, required this.color, this.size = 8});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// Compact status label such as "在线" with a leading dot.
class RdStatusPill extends StatelessWidget {
  final String label;
  final RdTone tone;
  final bool dot;
  const RdStatusPill(this.label,
      {super.key, this.tone = RdTone.neutral, this.dot = true});

  @override
  Widget build(BuildContext context) {
    final p = RdPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: tone.bg(p), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[
          RdStatusDot(color: tone.fg(p), size: 6),
          const SizedBox(width: 5),
        ],
        Text(label,
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
                color: tone.fg(p), fontWeight: FontWeight.w600, height: 1.3)),
      ]),
    );
  }
}

enum RdPlatform { windows, macos, android, ios, linux, unknown }

RdPlatform rdPlatformOf(String raw) {
  final v = raw.toLowerCase();
  // `darwin` contains `win`, so it has to be matched first.
  if (v.contains('mac') || v.contains('darwin')) return RdPlatform.macos;
  if (v.contains('win')) return RdPlatform.windows;
  if (v.contains('android')) return RdPlatform.android;
  if (v.contains('ios') || v.contains('ipad') || v.contains('iphone')) {
    return RdPlatform.ios;
  }
  if (v.contains('linux')) return RdPlatform.linux;
  return RdPlatform.unknown;
}

extension RdPlatformLabel on RdPlatform {
  String get label => switch (this) {
        RdPlatform.windows => 'Windows',
        RdPlatform.macos => 'macOS',
        RdPlatform.android => 'Android',
        RdPlatform.ios => 'iOS',
        RdPlatform.linux => 'Linux',
        RdPlatform.unknown => '未知系统',
      };
  IconData get icon => switch (this) {
        RdPlatform.windows => Icons.desktop_windows_rounded,
        RdPlatform.macos => Icons.laptop_mac_rounded,
        RdPlatform.android => Icons.phone_android_rounded,
        RdPlatform.ios => Icons.phone_iphone_rounded,
        RdPlatform.linux => Icons.computer_rounded,
        RdPlatform.unknown => Icons.devices_other_rounded,
      };
}

/// Device glyph with an online dot in the corner.
class RdDeviceGlyph extends StatelessWidget {
  final String platform;
  final bool? online;
  final double size;
  const RdDeviceGlyph(
      {super.key, required this.platform, this.online, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final p = RdPalette.of(context);
    final isOnline = online == true;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isOnline ? p.brandSoft : p.surfaceMuted,
            borderRadius: BorderRadius.circular(size * 0.28),
          ),
          child: Icon(rdPlatformOf(platform).icon,
              size: size * 0.52, color: isOnline ? p.brand : p.inkTertiary),
        ),
        if (online != null)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration:
                  BoxDecoration(color: p.surface, shape: BoxShape.circle),
              child: RdStatusDot(
                  color: isOnline ? p.online : p.inkTertiary,
                  size: size * 0.22),
            ),
          ),
      ]),
    );
  }
}

class RdEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  const RdEmptyState(
      {super.key,
      required this.icon,
      required this.title,
      this.message,
      this.action});

  @override
  Widget build(BuildContext context) {
    final p = RdPalette.of(context);
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Rd.s32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                  color: p.brandSoft,
                  borderRadius: BorderRadius.circular(Rd.radiusXl)),
              child: Icon(icon, size: 30, color: p.brand),
            ),
            const SizedBox(height: Rd.s16),
            Text(title, style: t.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, style: t.bodySmall, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: Rd.s20), action!],
          ]),
        ),
      ),
    );
  }
}

/// UU-style quick action: tinted icon above a short label.
class RdActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final RdTone tone;
  const RdActionButton(
      {super.key,
      required this.icon,
      required this.label,
      this.onTap,
      this.tone = RdTone.brand});

  @override
  Widget build(BuildContext context) {
    final p = RdPalette.of(context);
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Rd.radius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Opacity(
            opacity: enabled ? 1 : 0.45,
            child: RdIconBadge(icon: icon, tone: tone, size: 44),
          ),
          const SizedBox(height: 8),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium!.copyWith(
                  color: enabled ? p.ink : p.inkTertiary,
                  fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

/// Groups a numeric device ID for reading: 123 456 789.
String formatDeviceId(String id) {
  if (!RegExp(r'^\d{7,}$').hasMatch(id)) return id;
  final out = StringBuffer();
  for (var i = 0; i < id.length; i++) {
    if (i > 0 && (id.length - i) % 3 == 0) out.write(' ');
    out.write(id[i]);
  }
  return out.toString();
}

/// Scrollable page with a large title, centred on wide windows.
class RdPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;
  final Widget? leading;
  final double maxWidth;
  final Future<void> Function()? onRefresh;
  const RdPage(
      {super.key,
      required this.title,
      this.subtitle,
      this.actions = const [],
      required this.children,
      this.leading,
      this.maxWidth = Rd.contentMaxWidth,
      this.onRefresh});

  static bool wide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 720;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final isWide = wide(context);
    final pad = isWide ? Rd.pagePaddingDesktop : Rd.pagePadding;
    final list = ListView(
      padding: EdgeInsets.fromLTRB(pad, isWide ? 28 : 8, pad, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 8)],
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: isWide
                                  ? t.headlineSmall
                                  : t.headlineSmall!.copyWith(fontSize: 24)),
                          if (subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(subtitle!, style: t.bodySmall),
                          ],
                        ]),
                  ),
                  ...actions,
                ]),
                const SizedBox(height: Rd.s20),
                ...children,
              ],
            ),
          ),
        ),
      ],
    );
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: onRefresh == null
            ? list
            : RefreshIndicator(onRefresh: onRefresh!, child: list),
      ),
    );
  }
}
