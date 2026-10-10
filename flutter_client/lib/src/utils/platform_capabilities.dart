import 'package:flutter/foundation.dart';

class PlatformCapabilities {
  final TargetPlatform platform;
  const PlatformCapabilities.forPlatform(this.platform);
  static PlatformCapabilities get current =>
      PlatformCapabilities.forPlatform(defaultTargetPlatform);
  bool get isDesktop => {
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux
      }.contains(platform);
  bool get canHost => {
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.android,
        TargetPlatform.iOS
      }.contains(platform);
  bool get canUnattendedHost => {
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.android
      }.contains(platform);

  /// The desktop host implementation (`DesktopHostProvider`) serves this OS.
  bool get hasDesktopHost =>
      platform == TargetPlatform.macOS || platform == TargetPlatform.windows;

  /// No system prompt stands between the app and screen capture or input, so
  /// the user must switch hosting on in the app before it ever starts.
  bool get requiresHostOptIn => platform == TargetPlatform.windows;
  bool get canRelayWake => platform == TargetPlatform.android;
  bool get canScanPairing =>
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  bool get canConfigureLocalWake => platform == TargetPlatform.windows;
}
