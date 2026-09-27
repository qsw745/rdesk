import 'dart:io';

import 'package:flutter/services.dart';

class LoginItemState {
  final bool supported, enabled, requiresApproval;
  const LoginItemState(
      {this.supported = false,
      this.enabled = false,
      this.requiresApproval = false});
  factory LoginItemState.fromMap(Map<dynamic, dynamic>? m) => LoginItemState(
      supported: m?['supported'] == true,
      enabled: m?['enabled'] == true,
      requiresApproval: m?['requiresApproval'] == true);
}

/// Opens RDesk after the user logs in to macOS so a home Mac helper can be
/// restored after a restart. Changed only by the user's explicit switch.
class LoginItemService {
  static const _channel = MethodChannel('com.qsw.rdesk/login_item');
  const LoginItemService();

  Future<LoginItemState> status() async => Platform.isMacOS
      ? LoginItemState.fromMap(await _channel.invokeMethod('status'))
      : const LoginItemState();

  Future<LoginItemState> set(bool enabled) async => Platform.isMacOS
      ? LoginItemState.fromMap(await _channel.invokeMethod('set', enabled))
      : const LoginItemState();

  Future<void> openSettings() async {
    if (Platform.isMacOS) await _channel.invokeMethod('openSettings');
  }
}
