import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/home_screen.dart';
import '../screens/remote_desktop_screen.dart';
import '../screens/file_manager_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/connection_log_screen.dart';
import '../widgets/main_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    // ── Main shell with persistent bottom navigation ──
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return MainShell(navigationShell: navigationShell);
      },
      branches: [
        // Tab 0: 首页
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        // Tab 1: 连接历史
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/logs',
              builder: (context, state) => const ConnectionLogScreen(),
            ),
          ],
        ),
        // Tab 2: 设置
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),

    // ── Full-screen routes (no bottom nav) ──
    GoRoute(
      path: '/remote/:sessionId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => RemoteDesktopScreen(
        sessionId: state.pathParameters['sessionId']!,
      ),
    ),
    GoRoute(
      path: '/files/:sessionId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => FileManagerScreen(
        sessionId: state.pathParameters['sessionId']!,
      ),
    ),
    GoRoute(
      path: '/chat/:sessionId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => ChatScreen(
        sessionId: state.pathParameters['sessionId']!,
      ),
    ),
  ],
);
