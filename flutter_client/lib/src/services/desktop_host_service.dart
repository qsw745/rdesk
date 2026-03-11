import 'dart:io';
import 'dart:typed_data';

import 'android_host_service.dart'; // Reuse AndroidHostState / AndroidHostFrame

/// A pure-Dart host service for desktop (macOS / Windows / Linux).
///
/// On macOS it uses:
///   • `screencapture` CLI for screen capture (JPEG).
///   • Python + Quartz CGEvent for mouse / keyboard simulation.
///   • `pbcopy` / `pbpaste` for clipboard.
class DesktopHostService {
  DesktopHostService._();

  static final DesktopHostService instance = DesktopHostService._();

  bool _isRunning = false;
  int _frameSeq = 0;
  final String _capturePath =
      '${Directory.systemTemp.path}/rdesk_desktop_frame.jpg';

  // ---------- state ----------

  Future<AndroidHostState> getState() async {
    return AndroidHostState(
      state: _isRunning ? 'running' : 'idle',
      hasPermission: true, // Desktop doesn't need special permission flow
      isRunning: _isRunning,
      accessibilityEnabled: true,
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
    _frameSeq = 0;
    return getState();
  }

  Future<AndroidHostState> stopHosting() async {
    _isRunning = false;
    return getState();
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
    } catch (_) {
      return null;
    }
  }

  Future<AndroidHostFrame?> _captureMacOS() async {
    // -x = no sound, -t jpg = JPEG output, -C = capture cursor
    final result = await Process.run(
      'screencapture',
      ['-x', '-t', 'jpg', '-C', _capturePath],
      runInShell: false,
    );
    if (result.exitCode != 0) return null;

    final file = File(_capturePath);
    if (!file.existsSync()) return null;

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;

    // Decode image dimensions from JPEG header (SOF0 marker)
    final dims = _readJpegDimensions(bytes);
    _frameSeq++;

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
      await Process.run('open', [
        'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility',
      ]);
    }
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
        return false;
    }
  }

  // ---------- macOS CGEvent helpers via Python+Quartz ----------

  Future<(int, int)> _getScreenSize() async {
    final result = await Process.run('python3', [
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
    final script = '''
import Quartz, time
p = ($x, $y)
Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventMouseMoved, p, 0))
time.sleep(0.02)
Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseDown, p, 0))
time.sleep(0.05)
Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseUp, p, 0))
''';
    final result = await Process.run('python3', ['-c', script]);
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
    final result = await Process.run('python3', ['-c', script]);
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
    final result = await Process.run('python3', ['-c', script]);
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
    final result = await Process.run('python3', ['-c', script]);
    return result.exitCode == 0;
  }

  Future<bool> _macScroll(int amount) async {
    final script = '''
import Quartz
e = Quartz.CGEventCreateScrollWheelEvent(None, Quartz.kCGScrollEventUnitLine, 1, $amount)
Quartz.CGEventPost(Quartz.kCGHIDEventTap, e)
''';
    final result = await Process.run('python3', ['-c', script]);
    return result.exitCode == 0;
  }
}
