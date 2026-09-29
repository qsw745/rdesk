import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'windows_process_runner.dart';

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

typedef LoginItemRunner = Future<ProcessResult> Function(
    String executable, List<String> arguments);

/// Opens RDesk after the user signs in, so a Mac host or wake helper and a
/// Windows PC that was just woken come back online. Changed only by the user's
/// explicit switch (settings, remote-wake page or installer task).
///
/// Windows uses the current user's `Run` key only: no administrator task,
/// service or sign-in bypass. Windows "Startup apps" can disable the entry
/// through `StartupApproved\Run`; that counts as off, and turning the switch
/// on clears it so the two places never disagree.
class LoginItemService {
  static const _channel = MethodChannel('com.qsw.rdesk/login_item');
  static const _runKey = r'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _approvedKey =
      r'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';
  static const _valueName = 'RDesk';

  final TargetPlatform? _platform;
  final LoginItemRunner? _run;
  final String? _executable;
  const LoginItemService(
      {TargetPlatform? platform, LoginItemRunner? run, String? executable})
      : _platform = platform,
        _run = run,
        _executable = executable;

  TargetPlatform get platform => _platform ?? defaultTargetPlatform;
  bool get _isMac => platform == TargetPlatform.macOS;
  bool get _isWindows => platform == TargetPlatform.windows;

  Future<LoginItemState> status() async {
    if (_isMac) {
      return LoginItemState.fromMap(await _channel.invokeMethod('status'));
    }
    if (!_isWindows) return const LoginItemState();
    final out = await _powershell('''
\$v=\$null; \$a=\$null
try { \$v=Get-ItemPropertyValue -Path '$_runKey' -Name '$_valueName' -ErrorAction Stop } catch {}
try { \$a=Get-ItemPropertyValue -Path '$_approvedKey' -Name '$_valueName' -ErrorAction Stop } catch {}
\$off=(\$a -ne \$null) -and (@(\$a).Count -gt 0) -and ((@(\$a)[0] % 2) -eq 1)
if (\$v -and -not \$off) { 'true' } else { 'false' }''', '无法读取开机启动设置');
    return LoginItemState(supported: true, enabled: out.trim() == 'true');
  }

  Future<LoginItemState> set(bool enabled) async {
    if (_isMac) {
      return LoginItemState.fromMap(
          await _channel.invokeMethod('set', enabled));
    }
    if (!_isWindows) return const LoginItemState();
    final exe =
        (_executable ?? Platform.resolvedExecutable).replaceAll("'", "''");
    await _powershell(
        enabled
            ? '''
New-Item -Path '$_runKey' -Force | Out-Null
Set-ItemProperty -Path '$_runKey' -Name '$_valueName' -Value '"$exe"'
Remove-ItemProperty -Path '$_approvedKey' -Name '$_valueName' -ErrorAction SilentlyContinue'''
            : "Remove-ItemProperty -Path '$_runKey' -Name '$_valueName' -ErrorAction SilentlyContinue",
        '设置开机启动失败，请在 Windows「启动应用」中设置');
    return status();
  }

  Future<void> openSettings() async {
    if (_isMac) {
      await _channel.invokeMethod('openSettings');
    } else if (_isWindows) {
      await (_run ?? _defaultRun)(
          'cmd.exe', ['/c', 'start', '', 'ms-settings:startupapps']);
    }
  }

  Future<String> _powershell(String script, String failure) async {
    final result = await (_run ?? _defaultRun)('powershell.exe',
        ['-NoProfile', '-NonInteractive', '-Command', script]);
    if (result.exitCode != 0) throw LoginItemException(failure);
    return result.stdout.toString();
  }

  static Future<ProcessResult> _defaultRun(String exe, List<String> args) =>
      WindowsProcessRunner().run(exe, args);
}

class LoginItemException implements Exception {
  final String message;
  const LoginItemException(this.message);
  @override
  String toString() => message;
}
