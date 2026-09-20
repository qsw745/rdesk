import 'app_update_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../utils/platform_capabilities.dart';

class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const MainShell({super.key, required this.navigationShell});
  void _go(int index) => navigationShell.goBranch(index,
      initialLocation: index == navigationShell.currentIndex);
  @override
  Widget build(BuildContext context) {
    if (!PlatformCapabilities.current.isDesktop) {
      const indices = [0, 1, 4];
      final index = indices.indexOf(navigationShell.currentIndex);
      return Scaffold(
          body: Column(children: [
            const UpdateBanner(),
            Expanded(child: navigationShell)
          ]),
          bottomNavigationBar: NavigationBar(
              selectedIndex: index < 0 ? 0 : index,
              onDestinationSelected: (i) => _go(indices[i]),
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.devices_outlined),
                    selectedIcon: Icon(Icons.devices),
                    label: '设备'),
                NavigationDestination(
                    icon: Icon(Icons.connected_tv_outlined),
                    selectedIcon: Icon(Icons.connected_tv),
                    label: '协助'),
                NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: '我的'),
              ]));
    }
    final expanded = MediaQuery.sizeOf(context).width >= 900;
    final scheme = Theme.of(context).colorScheme;
    Widget destination(int index, String label, IconData icon) {
      final active = navigationShell.currentIndex == index;
      return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Tooltip(
              message: label,
              child: ListTile(
                onTap: () => _go(index),
                selected: active,
                selectedTileColor: scheme.primaryContainer,
                selectedColor: scheme.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding: EdgeInsets.symmetric(
                    horizontal: expanded ? 14 : 8, vertical: 4),
                leading: expanded ? Icon(icon, size: 22) : null,
                title: expanded
                    ? Text(label,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600))
                    : Icon(icon, size: 22, semanticLabel: label),
              )));
    }

    return Scaffold(
        body: Row(children: [
      Container(
          width: expanded ? 208 : 72,
          color: scheme.surface,
          child: SafeArea(
              child: Column(children: [
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Text(expanded ? 'RDesk' : 'R',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary))),
            Expanded(
                child: ListView(padding: EdgeInsets.zero, children: [
              destination(0, '设备', Icons.devices_outlined),
              destination(1, '远程协助', Icons.connected_tv_outlined),
              destination(2, '远程开机', Icons.power_settings_new),
            ])),
            destination(3, '设置', Icons.settings_outlined),
            destination(4, '账号', Icons.person_outline),
            const SizedBox(height: 16),
          ]))),
      const VerticalDivider(width: 1),
      Expanded(
          child: Column(children: [
        const UpdateBanner(),
        Expanded(child: navigationShell)
      ])),
    ]));
  }
}
