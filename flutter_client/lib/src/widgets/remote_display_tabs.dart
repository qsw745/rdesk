import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/remote_display.dart';
import '../providers/session_provider.dart';
import '../ui/tokens.dart';

/// One tab per screen of the computer being viewed. The selected screen sits
/// on a raised chip; the others share the recessed strip behind it.
class RemoteDisplayTabs extends StatefulWidget {
  const RemoteDisplayTabs({super.key});

  @override
  State<RemoteDisplayTabs> createState() => _RemoteDisplayTabsState();
}

class _RemoteDisplayTabsState extends State<RemoteDisplayTabs> {
  /// The tab whose switch the other computer has not confirmed yet.
  int? _switching;

  Future<void> _select(SessionProvider session, int position) async {
    if (_switching != null || position == session.currentMonitor) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final title = session.displays[position].title;
    setState(() => _switching = position);
    final switched = await session.setMonitor(position);
    if (!mounted) return;
    setState(() => _switching = null);
    if (!switched) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('没有切换到$title，对方电脑没有响应')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = RdPalette.of(context);
    final session = context.watch<SessionProvider>();
    final displays = session.displays;
    // The bar this sits in has a fixed height: larger text may grow a
    // little, but not until it is cut off.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.25,
      child: _strip(p, session, displays),
    );
  }

  Widget _strip(
      RdPalette p, SessionProvider session, List<RemoteDisplay> displays) {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        // Each tab fills the strip, so the selected one reads as a chip
        // rather than a line of text with a background.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < displays.length; i++)
            _DisplayTab(
              display: displays[i],
              selected: i == session.currentMonitor,
              busy: i == _switching,
              // With a single screen there is nothing to switch to.
              onTap: displays.length > 1 ? () => _select(session, i) : null,
            ),
        ],
      ),
    );
  }
}

class _DisplayTab extends StatelessWidget {
  const _DisplayTab({
    required this.display,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final RemoteDisplay display;
  final bool selected;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = RdPalette.of(context);
    final detail = display.detail;
    final radius = BorderRadius.circular(8);
    final tab = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected ? p.surface : p.surface.withValues(alpha: 0),
        borderRadius: radius,
        boxShadow: [
          if (selected)
            BoxShadow(
              color: p.ink.withValues(alpha: 0.10),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          hoverColor: p.ink.withValues(alpha: 0.05),
          focusColor: p.brand.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: busy
                      ? CircularProgressIndicator(
                          strokeWidth: 2, color: p.brand)
                      : Icon(
                          Icons.desktop_windows_outlined,
                          size: 16,
                          color: selected ? p.brand : p.inkTertiary,
                        ),
                ),
                const SizedBox(width: 8),
                Text(
                  display.title,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? p.ink : p.inkSecondary,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 190),
                    child: Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.2,
                        color: selected ? p.inkSecondary : p.inkTertiary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    final described = Semantics(
      button: onTap != null,
      selected: selected,
      label: display.label,
      // The ink well's own tap is hidden with the rest of the subtree.
      onTap: onTap,
      excludeSemantics: true,
      child: tab,
    );
    final description = display.description;
    return description.isEmpty
        ? described
        : Tooltip(
            message: description,
            waitDuration: const Duration(milliseconds: 500),
            child: described,
          );
  }
}
