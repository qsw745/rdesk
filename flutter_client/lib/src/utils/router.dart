import 'package:go_router/go_router.dart';
import '../screens/home_screen.dart';
import '../screens/remote_desktop_screen.dart';
import '../screens/file_manager_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/connection_log_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/remote/:sessionId',
      builder: (context, state) => RemoteDesktopScreen(
        sessionId: state.pathParameters['sessionId']!,
      ),
    ),
    GoRoute(
      path: '/files/:sessionId',
      builder: (context, state) => FileManagerScreen(
        sessionId: state.pathParameters['sessionId']!,
      ),
    ),
    GoRoute(
      path: '/chat/:sessionId',
      builder: (context, state) => ChatScreen(
        sessionId: state.pathParameters['sessionId']!,
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/logs',
      builder: (context, state) => const ConnectionLogScreen(),
    ),
  ],
);
