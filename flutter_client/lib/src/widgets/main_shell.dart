import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../ui/components.dart';
import '../ui/device_actions.dart';
import '../ui/tokens.dart';
import '../utils/platform_capabilities.dart';
import 'app_update_widgets.dart';

/// Branch order is fixed by the router: devices, assist, wake, settings, me.
class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  final String location;
  const MainShell(
      {super.key, required this.navigationShell, this.location = '/'});

  void _go(int index) => navigationShell.goBranch(index,
      initialLocation: index == navigationShell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final p = RdPalette.of(context);
    if (!PlatformCapabilities.current.isDesktop) {
      const indices = [0, 1, 4];
      // Wake and settings open from "我的" on phones.
      final index = const [0, 1, 2, 2, 2][navigationShell.currentIndex];
      return Scaffold(
        body: Column(children: [
          const UpdateBanner(),
          Expanded(child: navigationShell),
        ]),
        bottomNavigationBar: DecoratedBox(
          decoration:
              BoxDecoration(border: Border(top: BorderSide(color: p.divider))),
          child: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => _go(indices[i]),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.devices_outlined),
                  selectedIcon: Icon(Icons.devices_rounded),
                  label: '设备'),
              NavigationDestination(
                  icon: Icon(Icons.support_agent_outlined),
                  selectedIcon: Icon(Icons.support_agent_rounded),
                  label: '协助'),
              NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: '我的'),
            ],
          ),
        ),
      );
    }

    final expanded = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      body: Row(children: [
        _Sidebar(
            expanded: expanded,
            currentIndex: navigationShell.currentIndex,
            location: location,
            onBranch: _go),
        VerticalDivider(width: 1, color: p.divider),
        Expanded(
          child: Column(children: [
            const UpdateBanner(),
            Expanded(child: navigationShell),
          ]),
        ),
      ]),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final bool expanded;
  final int currentIndex;
  final String location;
  final ValueChanged<int> onBranch;
  const _Sidebar(
      {required this.expanded,
      required this.currentIndex,
      required this.location,
      required this.onBranch});

  @override
  Widget build(BuildContext context) {
    final p = RdPalette.of(context);
    final t = Theme.of(context).textTheme;
    final devices = watchDeviceDirectory(context);
    final onDevicePage = location.startsWith('/device/');

    Widget nav(int index, String label, IconData icon, IconData active) =>
        _NavItem(
            label: label,
            icon: currentIndex == index && !onDevicePage ? active : icon,
            selected: currentIndex == index && !onDevicePage,
            expanded: expanded,
            onTap: () => onBranch(index));

    return Container(
      width: expanded ? 244 : 76,
      color: p.sidebar,
      child: SafeArea(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(expanded ? 20 : 0, 22, 12, 18),
            child: Row(
              mainAxisAlignment:
                  expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Image.asset('assets/brand/mark.png', width: 30, height: 30),
                if (expanded) ...[
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text('随控',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleLarge!.copyWith(
                            fontWeight: FontWeight.w800, letterSpacing: 1)),
                  ),
                ],
              ],
            ),
          ),
          nav(0, '设备', Icons.devices_outlined, Icons.devices_rounded),
          nav(1, '远程协助', Icons.support_agent_outlined,
              Icons.support_agent_rounded),
          nav(2, '远程开机', Icons.power_settings_new_outlined,
              Icons.power_settings_new_rounded),
          if (expanded && devices.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 16, 6),
              child: Text('我的设备',
                  style: t.labelSmall!.copyWith(fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  for (final e in devices.take(30))
                    _DeviceItem(
                        name: e.name,
                        online: e.online,
                        selected: location == devicePath(e),
                        onTap: () => context.go(devicePath(e))),
                ],
              ),
            ),
          ] else
            const Spacer(),
          Divider(height: 1, color: p.divider),
          const SizedBox(height: 8),
          nav(3, '设置', Icons.settings_outlined, Icons.settings_rounded),
          _AccountItem(
              expanded: expanded,
              selected: currentIndex == 4,
              onTap: () => onBranch(4)),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected, expanded;
  final VoidCallback onTap;
  const _NavItem(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.expanded,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = RdPalette.of(context);
    final t = Theme.of(context).textTheme;
    final color = selected ? p.brand : p.inkSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Tooltip(
        message: expanded ? '' : label,
        child: Material(
          color: selected ? p.sidebarSelected : Colors.transparent,
          borderRadius: BorderRadius.circular(Rd.radiusSm + 2),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Rd.radiusSm + 2),
            child: SizedBox(
              height: 42,
              child: Row(
                mainAxisAlignment: expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  if (expanded) const SizedBox(width: 12),
                  Icon(icon, size: 21, color: color, semanticLabel: label),
                  if (expanded) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodyMedium!.copyWith(
                              color: selected ? p.brand : p.ink,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceItem extends StatelessWidget {
  final String name;
  final bool online, selected;
  final VoidCallback onTap;
  const _DeviceItem(
      {required this.name,
      required this.online,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = RdPalette.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Material(
        color: selected ? p.sidebarSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(Rd.radiusSm + 2),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Rd.radiusSm + 2),
          child: SizedBox(
            height: 36,
            child: Row(children: [
              const SizedBox(width: 18),
              RdStatusDot(color: online ? p.online : p.inkTertiary, size: 7),
              const SizedBox(width: 12),
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyMedium!.copyWith(
                        color: selected
                            ? p.brand
                            : online
                                ? p.ink
                                : p.inkSecondary,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400)),
              ),
              const SizedBox(width: 8),
            ]),
          ),
        ),
      ),
    );
  }
}

class _AccountItem extends StatelessWidget {
  final bool expanded, selected;
  final VoidCallback onTap;
  const _AccountItem(
      {required this.expanded, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final p = RdPalette.of(context);
    final t = Theme.of(context).textTheme;
    final session = auth.session;
    final name = session == null
        ? null
        : session.displayName.isNotEmpty
            ? session.displayName
            : session.username;
    final avatar = CircleAvatar(
      radius: 15,
      backgroundColor: auth.isLoggedIn ? p.brand : p.divider,
      child: auth.isLoggedIn && name != null && name.isNotEmpty
          ? Text(name.characters.first.toUpperCase(),
              style: t.labelMedium!.copyWith(color: Colors.white))
          : Icon(Icons.person_rounded, size: 18, color: p.inkTertiary),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Tooltip(
        message: expanded ? '' : '账号',
        child: Material(
          color: selected ? p.sidebarSelected : Colors.transparent,
          borderRadius: BorderRadius.circular(Rd.radiusSm + 2),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Rd.radiusSm + 2),
            child: SizedBox(
              height: 48,
              child: Row(
                mainAxisAlignment: expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  if (expanded) const SizedBox(width: 8),
                  avatar,
                  if (expanded) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(auth.isLoggedIn ? name ?? '已登录' : '登录账号',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodyMedium!.copyWith(
                              fontWeight: FontWeight.w500,
                              color: auth.isLoggedIn ? p.ink : p.brand)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
