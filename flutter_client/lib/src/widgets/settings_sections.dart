import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../ui/tokens.dart';
import '../utils/platform_capabilities.dart';

/// Settings page chrome: title, section switcher and a centred content column.
class SettingsSections extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;
  final List<Widget> children;
  const SettingsSections(
      {super.key,
      required this.selected,
      required this.onSelected,
      required this.children});
  static const labels = {
    'general': '常规',
    'security': '安全',
    'network': '网络',
    'about': '关于'
  };

  @override
  Widget build(BuildContext context) {
    final p = RdPalette.of(context);
    final t = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final pad = wide ? Rd.pagePaddingDesktop : Rd.pagePadding;
    final desktop = PlatformCapabilities.current.isDesktop;
    Widget column(Widget child) => Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920), child: child),
        );
    return SafeArea(
      bottom: false,
      child: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, wide ? 28 : 8, pad, 16),
          child: column(
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (!desktop) ...[
                IconButton(
                    onPressed: () => context.go('/me'),
                    tooltip: '返回',
                    icon: const Icon(Icons.arrow_back_rounded)),
                const SizedBox(width: 4),
              ],
              Text('设置',
                  style: wide
                      ? t.headlineSmall
                      : t.headlineSmall!.copyWith(fontSize: 24)),
            ]),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                  color: p.surfaceMuted,
                  borderRadius: BorderRadius.circular(Rd.radius),
                  border: Border.all(color: p.border)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (final entry in labels.entries)
                  _Segment(
                      label: entry.value,
                      selected: entry.key == selected,
                      onTap: () => onSelected(entry.key)),
              ]),
            ),
          ])),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 32),
            children: [
              column(Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children))
            ],
          ),
        ),
      ]),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Segment(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = RdPalette.of(context);
    return Material(
      color: selected ? p.surface : Colors.transparent,
      borderRadius: BorderRadius.circular(Rd.radiusSm + 1),
      elevation: selected ? 1 : 0,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rd.radiusSm + 1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Text(label,
              style: Theme.of(context).textTheme.labelLarge!.copyWith(
                  color: selected ? p.ink : p.inkSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
        ),
      ),
    );
  }
}
