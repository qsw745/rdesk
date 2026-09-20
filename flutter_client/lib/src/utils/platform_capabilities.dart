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
        TargetPlatform.android,
        TargetPlatform.iOS
      }.contains(platform);
  bool get canUnattendedHost =>
      platform == TargetPlatform.macOS || platform == TargetPlatform.android;
  bool get canRelayWake => platform == TargetPlatform.android;
  bool get canScanPairing =>
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  bool get canConfigureLocalWake => platform == TargetPlatform.windows;
}
