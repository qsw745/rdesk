// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
// UI screenshot harness (not part of the regular test suite).
//
//   flutter test tool/ui_shots/shots_test.dart --update-goldens [--plain-name ios_]
//
// Renders routes on each platform with real PingFang SC faces and seeded demo
// data, writing PNGs to tool/ui_shots/out/. Faces are extracted from the macOS
// PingFang.ttc by tool/ui_shots/extract_fonts.py into $RDESK_SHOT_FONTS.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rdesk/app.dart';
import 'package:rdesk/src/models/account.dart';
import 'package:rdesk/src/models/session.dart';
import 'package:rdesk/src/models/wake.dart';
import 'package:rdesk/src/providers/session_provider.dart';
import 'package:rdesk/src/providers/auth_provider.dart';
import 'package:rdesk/src/providers/wake_provider.dart';
import 'package:rdesk/src/utils/device_directory.dart';
import 'package:rdesk/src/utils/router.dart';
import 'package:rdesk/src/utils/theme.dart';

final fonts = Platform.environment['RDESK_SHOT_FONTS'] ?? '';
const materialIcons =
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
const server = 'https://qisw.top';

Future<void> loadFamily(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

class Shot {
  final String name, route;
  final TargetPlatform platform;
  final Size size;
  final bool seeded, dark;
  const Shot(this.name, this.route, this.platform, this.size,
      {this.seeded = true, this.dark = false});
}

const phone = Size(393, 852);
const desktop = Size(1280, 820);
String dev(String id) =>
    '/device/${Uri.encodeComponent(deviceDirectoryKey(server, id))}';

final shots = [
  const Shot('ios_devices_empty', '/', TargetPlatform.iOS, phone, seeded: false),
  const Shot('ios_devices', '/', TargetPlatform.iOS, phone),
  Shot('ios_device_online', dev('318204557'), TargetPlatform.iOS, phone),
  Shot('ios_device_wake', dev('552910384'), TargetPlatform.iOS, phone),
  const Shot('ios_assist', '/assist', TargetPlatform.iOS, phone),
  const Shot('ios_me', '/me', TargetPlatform.iOS, phone),
  const Shot('android_me', '/me', TargetPlatform.android, phone),
  const Shot('android_wake', '/wake', TargetPlatform.android, phone),
  const Shot('ios_devices_dark', '/', TargetPlatform.iOS, phone, dark: true),
  const Shot('mac_devices', '/', TargetPlatform.macOS, desktop),
  Shot('mac_device_online', dev('318204557'), TargetPlatform.macOS, desktop),
  const Shot('mac_assist', '/assist', TargetPlatform.macOS, desktop),
  const Shot('mac_wake', '/wake', TargetPlatform.macOS, desktop),
  const Shot('mac_settings', '/settings', TargetPlatform.macOS, desktop),
  const Shot('mac_settings_security', '/settings?section=security',
      TargetPlatform.macOS, desktop),
  const Shot('mac_settings_network', '/settings?section=network',
      TargetPlatform.macOS, desktop),
  const Shot('ios_settings_general', '/settings?section=general',
      TargetPlatform.iOS, phone),
  const Shot('ios_wake', '/wake', TargetPlatform.iOS, phone),
  const Shot('mac_me', '/me', TargetPlatform.macOS, desktop),
  const Shot('win_devices', '/', TargetPlatform.windows, desktop),
  const Shot('win_wake', '/wake', TargetPlatform.windows, desktop),
  const Shot('mac_devices_dark', '/', TargetPlatform.macOS, desktop, dark: true),
  const Shot('ios_remote', '/remote/demo', TargetPlatform.iOS, Size(852, 393)),
  const Shot('mac_remote', '/remote/demo', TargetPlatform.macOS, desktop),
  const Shot('ios_login', '/login', TargetPlatform.iOS, phone, seeded: false),
  const Shot('mac_register', '/register', TargetPlatform.macOS, desktop,
      seeded: false),
  const Shot('ios_logs', '/logs', TargetPlatform.iOS, phone),
  const Shot('ios_saved', '/saved', TargetPlatform.iOS, phone),
  const Shot('ios_gestures', '/gesture-guide', TargetPlatform.iOS, phone),
  const Shot('android_host', '/mobile-host', TargetPlatform.android, phone),
  const Shot('mac_unattended', '/unattended-setup', TargetPlatform.macOS,
      desktop),
];

void seed(BuildContext context) {
  final now = DateTime.now().millisecondsSinceEpoch;
  context.read<AuthProvider>().debugSeed(
      const AccountSession(
          token: 't', userId: 'u1', username: 'qsw', displayName: '青松'),
      [
        AccountDevice(
            deviceId: '318204557',
            hostname: '家里的 MacBook Pro',
            platform: 'macos',
            updatedAtMs: now),
        AccountDevice(
            deviceId: '720116093',
            hostname: '小米 14',
            platform: 'android',
            updatedAtMs: now),
      ],
      endpoint: server);
  final wake = context.read<WakeProvider>();
  wake.bindAccount('u1', server);
  wake.agents = const [
    WakeAgent(id: 'a1', name: '家中 Mac', online: true, enabled: true),
  ];
  wake.targets = const [
    WakeTarget(
        id: 't1',
        name: '书房台式机',
        deviceId: '552910384',
        mac: '00:11:22:33:44:55',
        agentId: 'a1',
        online: false,
        agentOnline: true,
        setupComplete: true,
        revision: 1),
  ];
  wake.notifyListeners();
  context.read<SessionProvider>().setSession(SessionInfo(
      sessionId: 'demo',
      peerId: '318204557',
      peerHostname: '家里的 MacBook Pro',
      peerOs: 'macos',
      state: SessionState.active,
      connectedAt: DateTime.now()));
}

void main() {
  setUpAll(() async {
    final faces = [
      for (final w in [300, 400, 500, 600, 700, 800]) '$fonts/PingFangSC-$w.ttf'
    ];
    await loadFamily('PingFang SC', faces);
    await loadFamily('MaterialIcons', [materialIcons]);
    AppTheme.debugFontFamily = 'PingFang SC';
  });
  for (final shot in shots) {
    testWidgets(shot.name, (tester) async {
      SharedPreferences.setMockInitialValues({
        'address_book_entries':
            '[{"deviceId":"640552781","endpointScope":"$server","alias":"公司工位电脑","group":"默认","platform":"macos","createdAt":1}]',
      });
      tester.platformDispatcher.platformBrightnessTestValue =
          shot.dark ? Brightness.dark : Brightness.light;
      tester.view.physicalSize = shot.size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      appRouter.go('/');
      await tester.pumpWidget(const RDeskApp());
      await tester.pump(const Duration(milliseconds: 300));
      if (shot.seeded) {
        seed(tester.element(find.byType(Navigator).first));
        await tester.pump(const Duration(milliseconds: 300));
        seed(tester.element(find.byType(Navigator).first));
      }
      appRouter.go(shot.route);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      await expectLater(
          find.byType(RDeskApp), matchesGoldenFile('out/${shot.name}.png'));
    }, variant: TargetPlatformVariant.only(shot.platform));
  }
}
