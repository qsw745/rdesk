import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'android_host_service.dart'; // Reuse AndroidHostState / AndroidHostFrame

class DesktopPermissionState {
  final bool screenRecordingGranted;
  final bool accessibilityGranted;

  const DesktopPermissionState({
    required this.screenRecordingGranted,
    required this.accessibilityGranted,
  });
}

class DesktopPermissionException implements Exception {
  final String code;
  final String message;

  const DesktopPermissionException(this.code, this.message);

  @override
  String toString() => message;
}

/// A pure-Dart host service for desktop (macOS / Windows / Linux).
///
/// On macOS it uses:
///   • `screencapture` CLI for screen capture (JPEG).
///   • Python + Quartz CGEvent for mouse / keyboard simulation.
///   • `pbcopy` / `pbpaste` for clipboard.
class DesktopHostService {
  DesktopHostService._();

  static final DesktopHostService instance = DesktopHostService._();
  static const _desktopChannel = MethodChannel('com.qsw.rdesk/desktop_host');

  bool _isRunning = false;
  final String _capturePath =
      '${Directory.systemTemp.path}/rdesk_desktop_frame.jpg';

  /// Once a screen capture succeeds, skip permission pre-checks to avoid
  /// triggering macOS system dialogs on every frame poll.
  bool _captureEverSucceeded = false;

  /// No longer used for latch — native side manages cooldown.
  /// Kept for resetPermissionDenied API compatibility.

  // ---------- state ----------

  Future<AndroidHostState> getState() async {
    final permission = await getPermissionState();
    return AndroidHostState(
      state: _isRunning ? 'running' : 'idle',
      hasPermission: permission.screenRecordingGranted,
      isRunning: _isRunning,
      accessibilityEnabled: permission.accessibilityGranted,
      overlayEnabled: true,
      notificationsEnabled: true,
      batteryOptimizationIgnored: true,
      manufacturer: 'desktop',
    );
  }

  Future<AndroidHostState> requestPermission() async {
    // On macOS, screen recording permission is requested automatically
    // the first time screencapture runs. Nothing to do here.
    return getState();
  }

  Future<AndroidHostState> startHosting() async {
    _isRunning = true;
    return getState();
  }

  Future<AndroidHostState> stopHosting() async {
    _isRunning = false;
    return getState();
  }

  // ---------- display management ----------

  Future<List<Map<String, dynamic>>> listDisplays() async {
    try {
      final result = await _desktopChannel.invokeListMethod<Map>('listDisplays');
      if (result == null) return [];
      return result
          .map((m) => Map<String, dynamic>.from(m as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> switchDisplay(int index) async {
    try {
      await _desktopChannel.invokeMethod('switchDisplay', {'index': index});
    } catch (_) {}
  }

  // ---------- screen capture ----------

  Future<AndroidHostFrame?> getLatestFrame() async {
    if (!_isRunning) return null;

    try {
      if (Platform.isMacOS) {
        return await _captureMacOS();
      }
      // TODO: Windows (nircmd / PowerShell), Linux (scrot / grim)
      return null;
    } catch (error) {
      if (error is DesktopPermissionException) {
        rethrow;
      }
      return null;
    }
  }

  /// Maximum dimension (width or height) for captured frames.
  static const _maxCaptureDimension = 1920;

  /// JPEG quality (0.0-1.0) for native capture. Adjustable via setJpegQuality().
  double _jpegQuality = 0.8;

  /// Update JPEG capture quality (0.0-1.0).
  void setJpegQuality(double quality) {
    _jpegQuality = quality.clamp(0.1, 1.0);
  }

  /// Current JPEG quality.
  double get jpegQuality => _jpegQuality;

  /// Reset permission denied cooldown on the native side.
  /// Call after the user navigates to System Settings to grant permission.
  Future<void> resetPermissionDenied() async {
    try {
      await _desktopChannel.invokeMethod('resetPermissionDenied');
    } catch (_) {}
  }

  Future<AndroidHostFrame?> _captureMacOS() async {
    try {
      // Use native ScreenCaptureKit via MethodChannel.
      // Returns JPEG bytes directly in memory — no disk I/O.
      final captureResult = await _desktopChannel
          .invokeMapMethod<String, dynamic>('captureScreen', {
        'maxDimension': _maxCaptureDimension,
        'quality': _jpegQuality,
      }).timeout(const Duration(seconds: 5));

      if (captureResult == null) return null;

      final width = captureResult['width'] as int? ?? 0;
      final height = captureResult['height'] as int? ?? 0;
      if (width == 0 || height == 0) return null;

      // Receive JPEG bytes directly from native (no disk I/O).
      Uint8List bytes;
      final rawBytes = captureResult['bytes'];
      if (rawBytes is Uint8List && rawBytes.isNotEmpty) {
        bytes = rawBytes;
      } else if (rawBytes is List) {
        // MethodChannel may decode as List<int> instead of Uint8List.
        bytes = Uint8List.fromList(rawBytes.cast<int>());
        if (bytes.isEmpty) return null;
      } else {
        // Legacy fallback: read from file path if native returns path.
        final path = captureResult['path'] as String?;
        if (path == null) {
          debugPrint('[RDesk] captureScreen returned no bytes and no path. '
              'Result keys: ${captureResult.keys.toList()}, '
              'bytes type: ${rawBytes?.runtimeType}');
          return null;
        }
        final file = File(path);
        if (!file.existsSync()) return null;
        bytes = await file.readAsBytes();
        if (bytes.isEmpty) return null;
      }

      _captureEverSucceeded = true;
      return AndroidHostFrame(
        bytes: bytes,
        width: width,
        height: height,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        // Native side manages cooldown — just throw so the provider knows.
        throw DesktopPermissionException(
          'screen_recording_denied',
          e.message ?? '屏幕录制权限未授予，请在系统设置中授权后会自动恢复',
        );
      }
      _captureEverSucceeded = false;
      throw DesktopPermissionException(
        'capture_failed',
        '屏幕采集失败：${e.message}',
      );
    } on TimeoutException {
      // MethodChannel timed out — fall back to screencapture CLI.
      debugPrint('[RDesk] Native capture timed out, falling back to screencapture CLI');
      return _captureMacOSFallback();
    } catch (e) {
      // MethodChannel unavailable — fall back to screencapture CLI as last resort.
      // But NOT for permission errors — those should propagate up.
      if (e is DesktopPermissionException) rethrow;
      debugPrint('[RDesk] Native capture unavailable, falling back to screencapture CLI: $e');
      return _captureMacOSFallback();
    }
  }

  /// Fallback: use screencapture CLI (only if native channel is unavailable).
  Future<AndroidHostFrame?> _captureMacOSFallback() async {
    final result = await Process.run(
      'screencapture',
      ['-x', '-t', 'jpg', '-C', _capturePath],
      runInShell: false,
    );
    if (result.exitCode != 0) {
      _captureEverSucceeded = false;
      return null; // Silently fail — don't trigger dialogs.
    }

    final file = File(_capturePath);
    if (!file.existsSync()) return null;

    _captureEverSucceeded = true;
    var bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;

    final dims = _readJpegDimensions(bytes);
    return AndroidHostFrame(
      bytes: bytes,
      width: dims.$1,
      height: dims.$2,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  (int width, int height) _readJpegDimensions(Uint8List data) {
    // Scan for SOF0 (0xFF 0xC0) or SOF2 (0xFF 0xC2) marker
    for (var i = 0; i < data.length - 9; i++) {
      if (data[i] == 0xFF && (data[i + 1] == 0xC0 || data[i + 1] == 0xC2)) {
        final height = (data[i + 5] << 8) | data[i + 6];
        final width = (data[i + 7] << 8) | data[i + 8];
        if (width > 0 && height > 0) return (width, height);
      }
    }
    // Fallback: assume common resolution
    return (1920, 1080);
  }

  // ---------- input simulation ----------

  Future<void> showRemoteTapIndicator({
    required double normalizedX,
    required double normalizedY,
  }) async {
    // Visual indicator not needed on desktop (cursor shows position)
  }

  Future<bool> performRemoteTap({
    required double normalizedX,
    required double normalizedY,
  }) async {
    if (Platform.isMacOS) {
      return _macMouseClick(normalizedX, normalizedY);
    }
    return false;
  }

  Future<bool> performRemoteLongPress({
    required double normalizedX,
    required double normalizedY,
  }) async {
    // On desktop, long press = right click
    if (Platform.isMacOS) {
      return _macMouseRightClick(normalizedX, normalizedY);
    }
    return false;
  }

  Future<bool> performRemoteDrag({
    required double startX,
    required double startY,
    required double endX,
    required double endY,
  }) async {
    if (Platform.isMacOS) {
      return _macMouseDrag(startX, startY, endX, endY);
    }
    return false;
  }

  Future<bool> performRemoteTextInput(String text) async {
    if (Platform.isMacOS) {
      return _macTypeText(text);
    }
    return false;
  }

  Future<bool> setClipboardText(String text) async {
    if (Platform.isMacOS) {
      final process = await Process.start('pbcopy', []);
      process.stdin.write(text);
      await process.stdin.close();
      final exitCode = await process.exitCode;
      return exitCode == 0;
    }
    return false;
  }

  Future<String?> getClipboardText() async {
    if (Platform.isMacOS) {
      final result = await Process.run('pbpaste', []);
      if (result.exitCode == 0) return result.stdout as String;
    }
    return null;
  }

  Future<void> openAccessibilitySettings() async {
    if (Platform.isMacOS) {
      try {
        await _desktopChannel.invokeMethod<void>('openAccessibilitySettings');
        return;
      } catch (_) {}
      await Process.run('open', [
        'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'
      ]);
    }
  }

  Future<void> openScreenRecordingSettings() async {
    if (Platform.isMacOS) {
      try {
        await _desktopChannel.invokeMethod<void>('openScreenRecordingSettings');
        return;
      } catch (_) {}
      await Process.run('open', [
        'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture'
      ]);
    }
  }

  Future<void> activateAppWindow() async {
    if (!Platform.isMacOS) return;
    try {
      await _desktopChannel.invokeMethod<void>('activateApp');
    } catch (_) {}
  }

  Future<bool> performRemoteAction(String action) async {
    if (!Platform.isMacOS) return false;
    // Desktop doesn't have Android-style back/home/recents.
    // Map to reasonable keyboard shortcuts.
    switch (action) {
      case 'scroll_up':
        return _macScroll(3);
      case 'scroll_down':
        return _macScroll(-3);
      case 'delete':
        return _macKeyPress(51, 0); // keycode 51 = Delete
      case 'enter':
        return _macKeyPress(36, 0); // keycode 36 = Return
      case 'back':
        // Cmd+[ as "back" on macOS
        return _macKeyPress(33, 'command'); // keycode 33 = [
      case 'home':
        // Cmd+H = hide current app (closest to "home")
        return _macKeyPress(4, 'command'); // keycode 4 = H
      case 'recents':
        // Mission Control: Ctrl+Up
        return _macKeyPress(126, 'control'); // keycode 126 = UpArrow
      default:
        if (action.startsWith('switch_monitor_')) {
          final idx = int.tryParse(action.substring('switch_monitor_'.length));
          if (idx != null) {
            await switchDisplay(idx);
            return true;
          }
        }
        return false;
    }
  }

  Future<DesktopPermissionState> getPermissionState() async {
    if (!Platform.isMacOS) {
      return const DesktopPermissionState(
        screenRecordingGranted: true,
        accessibilityGranted: true,
      );
    }

    // If a capture has already succeeded, we know permission is granted.
    if (_captureEverSucceeded) {
      return const DesktopPermissionState(
        screenRecordingGranted: true,
        accessibilityGranted: true,
      );
    }

    var screenRecordingGranted = false;
    var accessibilityGranted = false;
    try {
      final result = await _desktopChannel
          .invokeMapMethod<String, dynamic>('getPermissionState')
          .timeout(const Duration(seconds: 2));
      screenRecordingGranted =
          (result?['screenRecordingGranted'] as bool?) ?? false;
      accessibilityGranted =
          (result?['accessibilityGranted'] as bool?) ?? false;
    } catch (_) {
      // Native channel unavailable — optimistically assume granted so the
      // actual capture attempt can proceed and fail naturally if needed.
      screenRecordingGranted = true;
      accessibilityGranted = true;
    }
    // NOTE: We deliberately do NOT fall back to _probeScreenRecordingPermission()
    // here. The probe runs `screencapture` which triggers the macOS system
    // permission dialog on every call when CGPreflightScreenCaptureAccess()
    // returns false (common on macOS 15+ / Tahoe). Instead we trust the
    // native CGPreflightScreenCaptureAccess() result and let the actual
    // capture attempt in _captureMacOS() determine the real permission state.
    return DesktopPermissionState(
      screenRecordingGranted: screenRecordingGranted,
      accessibilityGranted: accessibilityGranted,
    );
  }

  Future<DesktopPermissionState> requestPermissionPrompts() async {
    if (!Platform.isMacOS) {
      return const DesktopPermissionState(
        screenRecordingGranted: true,
        accessibilityGranted: true,
      );
    }
    try {
      final result = await _desktopChannel
          .invokeMapMethod<String, dynamic>('requestPermissionPrompts')
          .timeout(const Duration(seconds: 2));
      return DesktopPermissionState(
        screenRecordingGranted:
            (result?['screenRecordingGranted'] as bool?) ?? false,
        accessibilityGranted:
            (result?['accessibilityGranted'] as bool?) ?? false,
      );
    } catch (_) {
      return getPermissionState();
    }
  }

  // ---------- macOS CGEvent helpers via Python+Quartz ----------

  Future<(int, int)> _getScreenSize() async {
    final result = await Process.run('/Library/Frameworks/Python.framework/Versions/3.13/bin/python3', [
      '-c',
      'import Quartz; d=Quartz.CGDisplayBounds(Quartz.CGMainDisplayID()); print(int(d.size.width), int(d.size.height))',
    ]);
    if (result.exitCode == 0) {
      final parts = (result.stdout as String).trim().split(' ');
      if (parts.length == 2) {
        return (int.tryParse(parts[0]) ?? 1920, int.tryParse(parts[1]) ?? 1080);
      }
    }
    return (1920, 1080);
  }

  Future<(double, double)> _normalizedToAbsolute(double nx, double ny) async {
    final screen = await _getScreenSize();
    return (nx * screen.$1, ny * screen.$2);
  }

  Future<bool> _macMouseClick(double nx, double ny) async {
    final (x, y) = await _normalizedToAbsolute(nx, ny);
    debugPrint('[RDesk] _macMouseClick: normalized=($nx, $ny) → absolute=($x, $y)');
    final script = '''
import Quartz, time, sys
p = ($x, $y)
# Check if we can create events (accessibility permission)
evt = Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventMouseMoved, p, 0)
if evt is None:
    print("ERROR: Cannot create CGEvent - accessibility permission likely denied", file=sys.stderr)
    sys.exit(1)
Quartz.CGEventPost(Quartz.kCGHIDEventTap, evt)
time.sleep(0.02)
Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseDown, p, 0))
time.sleep(0.05)
Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseUp, p, 0))
print(f"OK: clicked at {p}")
''';
    final result = await Process.run('/Library/Frameworks/Python.framework/Versions/3.13/bin/python3', ['-c', script]);
    if (result.exitCode != 0) {
      debugPrint('[RDesk] _macMouseClick FAILED: exit=${result.exitCode} '
          'stderr=${result.stderr}');
    } else {
      debugPrint('[RDesk] _macMouseClick: ${(result.stdout as String).trim()}');
    }
    return result.exitCode == 0;
  }

  Future<bool> _macMouseRightClick(double nx, double ny) async {
    final (x, y) = await _normalizedToAbsolute(nx, ny);
    final script = '''
import Quartz, time
p = ($x, $y)
Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventMouseMoved, p, 0))
time.sleep(0.02)
Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventRightMouseDown, p, Quartz.kCGMouseButtonRight))
time.sleep(0.05)
Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventRightMouseUp, p, Quartz.kCGMouseButtonRight))
''';
    final result = await Process.run('/Library/Frameworks/Python.framework/Versions/3.13/bin/python3', ['-c', script]);
    return result.exitCode == 0;
  }

  Future<bool> _macMouseDrag(double sx, double sy, double ex, double ey) async {
    final (startX, startY) = await _normalizedToAbsolute(sx, sy);
    final (endX, endY) = await _normalizedToAbsolute(ex, ey);
    final script = '''
import Quartz, time
sp = ($startX, $startY)
ep = ($endX, $endY)
Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventMouseMoved, sp, 0))
time.sleep(0.02)
Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseDown, sp, 0))
steps = 10
for i in range(1, steps + 1):
    t = i / steps
    x = sp[0] + (ep[0] - sp[0]) * t
    y = sp[1] + (ep[1] - sp[1]) * t
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseDragged, (x, y), 0))
    time.sleep(0.02)
Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseUp, ep, 0))
''';
    final result = await Process.run('/Library/Frameworks/Python.framework/Versions/3.13/bin/python3', ['-c', script]);
    return result.exitCode == 0;
  }

  Future<bool> _macTypeText(String text) async {
    // Use AppleScript for reliable text input (handles Unicode)
    final escaped = text.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    final result = await Process.run('osascript', [
      '-e',
      'tell application "System Events" to keystroke "$escaped"',
    ]);
    return result.exitCode == 0;
  }

  Future<bool> _macKeyPress(int keyCode, [dynamic modifier]) async {
    final script = '''
import Quartz
e = Quartz.CGEventCreateKeyboardEvent(None, $keyCode, True)
${modifier == 'command' ? 'Quartz.CGEventSetFlags(e, Quartz.kCGEventFlagMaskCommand)' : modifier == 'control' ? 'Quartz.CGEventSetFlags(e, Quartz.kCGEventFlagMaskControl)' : ''}
Quartz.CGEventPost(Quartz.kCGHIDEventTap, e)
e2 = Quartz.CGEventCreateKeyboardEvent(None, $keyCode, False)
${modifier == 'command' ? 'Quartz.CGEventSetFlags(e2, Quartz.kCGEventFlagMaskCommand)' : modifier == 'control' ? 'Quartz.CGEventSetFlags(e2, Quartz.kCGEventFlagMaskControl)' : ''}
Quartz.CGEventPost(Quartz.kCGHIDEventTap, e2)
''';
    final result = await Process.run('/Library/Frameworks/Python.framework/Versions/3.13/bin/python3', ['-c', script]);
    return result.exitCode == 0;
  }

  Future<bool> _macScroll(int amount) async {
    final script = '''
import Quartz
e = Quartz.CGEventCreateScrollWheelEvent(None, Quartz.kCGScrollEventUnitLine, 1, $amount)
Quartz.CGEventPost(Quartz.kCGHIDEventTap, e)
''';
    final result = await Process.run('/Library/Frameworks/Python.framework/Versions/3.13/bin/python3', ['-c', script]);
    return result.exitCode == 0;
  }
}
