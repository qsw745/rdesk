import 'dart:io';
import 'dart:async';

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
import 'src/providers/address_book_provider.dart';
import 'src/providers/desktop_host_provider.dart';
import 'src/utils/router.dart';
import 'src/utils/theme.dart';

/// Whether the current platform is a desktop OS (macOS, Windows, Linux).
bool get _isDesktopPlatform {
  if (kIsWeb) return false;
  return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
}

/// Whether the current platform is a mobile OS (Android or iOS).
/// Both use the same `com.qsw.rdesk/android_host` MethodChannel for
/// screen capture and host functionality.
bool get _isMobilePlatform {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android || Platform.isIOS;
}

class RDeskApp extends StatelessWidget {
  const RDeskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
            create: (_) => ConnectionProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => SessionProvider()),
        ChangeNotifierProvider(
            create: (_) => SettingsProvider()..loadSettings()),
        ChangeNotifierProvider(create: (_) => AuthProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => FileTransferProvider()),
        ChangeNotifierProvider(create: (_) => AddressBookProvider()..load()),
        ChangeNotifierProvider(
          lazy: false,
          create: (_) =>
              AndroidHostProvider()..initialize(enabled: _isMobilePlatform),
        ),
        ChangeNotifierProvider(
          lazy: false,
          create: (_) {
            final provider = DesktopHostProvider();
            if (_isDesktopPlatform) {
              unawaited(provider.initialize(enabled: true));
              unawaited(provider.startHosting());
            }
            return provider;
          },
        ),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return GestureDetector(
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: MaterialApp.router(
              title: 'RDesk 远程桌面',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: _getThemeMode(settings.theme),
              routerConfig: appRouter,
              locale: const Locale('zh', 'CN'),
            ),
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
