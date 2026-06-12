import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/remote_desktop_screen.dart';
import '../screens/file_manager_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/connection_settings_screen.dart';
import '../screens/gesture_guide_screen.dart';
import '../screens/shortcut_guide_screen.dart';
import '../screens/connection_log_screen.dart';
import '../screens/my_devices_screen.dart';
import '../screens/cloud_devices_screen.dart';
import '../screens/remote_assist_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/address_book_screen.dart';
import '../screens/unattended_setup_screen.dart';
import '../screens/device_detail_screen.dart';
import '../screens/account_auth_screen.dart';
import '../screens/mobile_host_screen.dart';
import '../widgets/main_shell.dart';
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
        // Tab 0: 我的设备
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const MyDevicesScreen(),
            ),
          ],
        ),
        // Tab 1: 云设备
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/cloud',
              builder: (context, state) => const CloudDevicesScreen(),
            ),
          ],
        ),
        // Tab 2: 远程协助
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/assist',
              builder: (context, state) => const RemoteAssistScreen(),
            ),
          ],
        ),
        // Tab 3: 地址簿
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/addressbook',
              builder: (context, state) => const AddressBookScreen(),
            ),
          ],
        ),
        // Tab 4: 我的
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/me',
              builder: (context, state) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    ),

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
      path: '/chat/:sessionId',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => ChatScreen(
        sessionId: state.pathParameters['sessionId']!,
      ),
    ),
    GoRoute(
      path: '/settings',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const SettingsScreen(),
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
      path: '/connection-settings',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const ConnectionSettingsScreen(),
    ),
    GoRoute(
      path: '/mobile-host',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const MobileHostScreen(),
    ),
    GoRoute(
      path: '/gesture-guide',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const GestureGuideScreen(),
    ),
    GoRoute(
      path: '/shortcut-guide',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const ShortcutGuideScreen(),
    ),
    GoRoute(
      path: '/logs',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const ConnectionLogScreen(),
    ),
    GoRoute(
      path: '/unattended-setup',
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
