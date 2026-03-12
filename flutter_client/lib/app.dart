import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'src/providers/connection_provider.dart';
import 'src/providers/session_provider.dart';
import 'src/providers/settings_provider.dart';
import 'src/providers/chat_provider.dart';
import 'src/providers/file_transfer_provider.dart';
import 'src/providers/android_host_provider.dart';
import 'src/providers/auth_provider.dart';
import 'src/providers/desktop_host_provider.dart';
import 'src/utils/router.dart';
import 'src/utils/theme.dart';

/// Whether the current platform is a desktop OS (macOS, Windows, Linux).
bool get _isDesktopPlatform {
  if (kIsWeb) return false;
  return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
}

/// Whether the current platform is Android.
bool get _isAndroidPlatform {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android;
}

class RDeskApp extends StatelessWidget {
  const RDeskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectionProvider()),
        ChangeNotifierProvider(create: (_) => SessionProvider()),
        ChangeNotifierProvider(
            create: (_) => SettingsProvider()..loadSettings()),
        ChangeNotifierProvider(create: (_) => AuthProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => FileTransferProvider()),
        // Android host — only enabled on Android
        ChangeNotifierProvider(
          create: (_) => AndroidHostProvider()
            ..initialize(enabled: _isAndroidPlatform),
        ),
        // Desktop host — enabled on macOS / Windows / Linux.
        // Auto-starts hosting so this machine is immediately discoverable
        // by other devices (iPhone, Android, etc.).
        ChangeNotifierProvider(
          create: (_) {
            final provider = DesktopHostProvider();
            if (_isDesktopPlatform) {
              provider.initialize(enabled: true).then((_) {
                provider.startHosting();
              });
            }
            return provider;
          },
        ),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return MaterialApp.router(
            title: 'RDesk 远程桌面',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: _getThemeMode(settings.theme),
            routerConfig: appRouter,
            locale: const Locale('zh', 'CN'),
          );
        },
      ),
    );
  }

  ThemeMode _getThemeMode(String theme) {
    switch (theme) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
