import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/remote_desktop_screen.dart';
import '../screens/file_manager_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/wake_screen.dart';
import '../screens/windows_wake_screen.dart';
import '../screens/wake_pairing_scan_screen.dart';
import '../screens/wake_mobile_setup_screen.dart';
import '../screens/gesture_guide_screen.dart';
import '../screens/connection_log_screen.dart';
import '../screens/my_devices_screen.dart';
import '../screens/remote_assist_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/address_book_screen.dart';
import '../screens/unattended_setup_screen.dart';
import '../screens/device_detail_screen.dart';
import '../screens/account_auth_screen.dart';
import '../screens/mobile_host_screen.dart';
import '../widgets/main_shell.dart';
import 'platform_capabilities.dart';
import '../widgets/account_auth_dialog.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  routes: [
    // ── Main shell with persistent bottom navigation ──
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return MainShell(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/',
              builder: (_, state) => MyDevicesScreen(
                  initialFilter: state.uri.queryParameters['filter'] ?? '全部'))
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/assist', builder: (_, __) => const RemoteAssistScreen())
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/wake',
              builder: (_, __) =>
                  PlatformCapabilities.current.canConfigureLocalWake
                      ? const WindowsWakeScreen()
                      : const WakeScreen())
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/settings',
              builder: (_, state) => SettingsScreen(
                  initialSection:
                      state.uri.queryParameters['section'] ?? 'general'))
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/me', builder: (_, __) => const ProfileScreen())
        ]),
      ],
    ),
    GoRoute(path: '/cloud', redirect: (_, __) => '/'),
    GoRoute(path: '/addressbook', redirect: (_, __) => '/?filter=收藏'),
    GoRoute(
        path: '/connection-settings',
        redirect: (_, __) => '/settings?section=network'),
    GoRoute(
        path: '/wake/scan',
        parentNavigatorKey: rootNavigatorKey,
        redirect: (_, __) =>
            PlatformCapabilities.current.canScanPairing ? null : '/wake',
        builder: (_, __) => const WakePairingScanScreen()),
    GoRoute(
        path: '/wake/target/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) =>
            WakeMobileSetupScreen(targetId: state.pathParameters['id']!)),
    GoRoute(
        path: '/wake/setup',
        redirect: (_, __) => PlatformCapabilities.current.canScanPairing
            ? '/wake/scan'
            : '/wake'),
    GoRoute(
        path: '/saved',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, __) => const AddressBookScreen()),
    // ── Full-screen routes (no bottom nav) ──
    GoRoute(
      path: '/remote/:sessionId',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => RemoteDesktopScreen(
        sessionId: state.pathParameters['sessionId']!,
      ),
    ),
    GoRoute(
      path: '/files/:sessionId',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => FileManagerScreen(
        sessionId: state.pathParameters['sessionId']!,
      ),
    ),
    GoRoute(
      path: '/login',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => AccountAuthScreen(
        mode: AccountAuthMode.login,
        redirect: state.uri.queryParameters['redirect'],
      ),
    ),
    GoRoute(
      path: '/register',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => AccountAuthScreen(
        mode: AccountAuthMode.register,
        redirect: state.uri.queryParameters['redirect'],
      ),
    ),
    GoRoute(
      path: '/mobile-host',
      redirect: (_, __) =>
          PlatformCapabilities.current.canScanPairing ? null : '/settings',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const MobileHostScreen(),
    ),
    GoRoute(
      path: '/gesture-guide',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const GestureGuideScreen(),
    ),
    GoRoute(
      path: '/logs',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const ConnectionLogScreen(),
    ),
    GoRoute(
      path: '/unattended-setup',
      redirect: (_, __) => PlatformCapabilities.current.canUnattendedHost
          ? null
          : '/settings?section=security',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const UnattendedSetupScreen(),
    ),
    GoRoute(
      path: '/device-detail/:deviceId',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) {
        final extra = state.extra as Map<String, String>? ?? {};
        return DeviceDetailScreen(
          deviceId: state.pathParameters['deviceId']!,
          hostname: extra['hostname'] ?? '远程设备',
          platform: extra['platform'] ?? '未知',
        );
      },
    ),
  ],
);
