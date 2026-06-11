import Cocoa
import FlutterMacOS
import ApplicationServices
import CoreGraphics
import ScreenCaptureKit

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Register desktop host channel with binary messenger.
    DesktopHostPlugin.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

// MARK: - DesktopHostPlugin

/// Handles desktop host MethodChannel: screen capture (ScreenCaptureKit), permissions.
class DesktopHostPlugin {
  private static let channelName = "com.qsw.rdesk/desktop_host"
  /// Currently selected display index (0 = main display).
  private static var _selectedDisplayIndex = 0

  // MARK: Permission state tracking

  /// True after SCKit capture succeeds at least once this launch.
  private static var _screenCaptureEverSucceeded = false

  /// Timestamp when the last TCC denial was observed.
  /// Used to implement a cooldown — we won't call SCKit again until
  /// `_denialCooldownSeconds` have passed.
  private static var _lastDenialTime: Date? = nil
  /// Cooldown in seconds after a denial before we attempt SCKit again.
  /// This prevents popup-spam while still allowing auto-recovery
  /// after the user grants permission in System Settings.
  private static let _denialCooldownSeconds: TimeInterval = 30

  /// True after we've called CGRequestScreenCaptureAccess() once.
  /// Prevents repeated system prompts (CG API, not SCKit).
  private static var _screenPermissionRequested = false
  private static var _accessibilityPermissionRequested = false

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getPermissionState":
        result(currentPermissionState())
      case "requestPermissionPrompts":
        requestPermissionPrompts()
        result(currentPermissionState())
      case "resetPermissionDenied":
        // Called after user navigates to Settings — clear cooldown to allow immediate retry.
        _lastDenialTime = nil
        result(nil)
      case "captureScreen":
        let args = call.arguments as? [String: Any]
        let maxDim = args?["maxDimension"] as? Int ?? 1920
        let quality = args?["quality"] as? Double ?? 0.5
        captureScreen(maxDimension: maxDim, quality: quality, result: result)
      case "listDisplays":
        listDisplays(result: result)
      case "switchDisplay":
        let args = call.arguments as? [String: Any]
        let index = args?["index"] as? Int ?? 0
        _selectedDisplayIndex = index
        NSLog("[RDesk] switchDisplay: index=\(index)")
        result(nil)
      case "openScreenRecordingSettings":
        openSystemSettings(anchor: "Privacy_ScreenCapture")
        result(nil)
      case "openAccessibilitySettings":
        openSystemSettings(anchor: "Privacy_Accessibility")
        result(nil)
      case "activateApp":
        NSApp.activate(ignoringOtherApps: true)
        NSApp.mainWindow?.makeKeyAndOrderFront(nil)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: Display listing (CG-based, no TCC prompt)

  /// List displays using CoreGraphics — never triggers a permission prompt.
  private static func listDisplays(result: @escaping FlutterResult) {
    var cgDisplayIDs = [CGDirectDisplayID](repeating: 0, count: 10)
    var cgCount: UInt32 = 0
    CGGetOnlineDisplayList(10, &cgDisplayIDs, &cgCount)
    let mainID = CGMainDisplayID()

    // Build display info from CG (always available, no TCC).
    var displays: [(id: CGDirectDisplayID, width: Int, height: Int)] = []
    for i in 0..<Int(cgCount) {
      let did = cgDisplayIDs[i]
      let bounds = CGDisplayBounds(did)
      displays.append((did, Int(bounds.width), Int(bounds.height)))
    }

    // Sort: main display first, then by displayID.
    displays.sort { a, b in
      if a.id == mainID { return true }
      if b.id == mainID { return false }
      return a.id < b.id
    }

    let list = displays.enumerated().map { (i, d) -> [String: Any] in
      let isMain = d.id == mainID
      let name = isMain ? "主显示器" : "显示器 \(i + 1)"
      return [
        "index": i,
        "name": "\(name) (\(d.width)×\(d.height))",
        "width": d.width,
        "height": d.height,
        "isMain": isMain,
      ]
    }
    NSLog("[RDesk] listDisplays: \(list.count) displays, mainID=\(mainID)")
    result(list)
  }

  // MARK: Screen Capture

  /// Check if we're in cooldown after a TCC denial.
  private static var _isInDenialCooldown: Bool {
    guard let lastDenial = _lastDenialTime else { return false }
    return Date().timeIntervalSince(lastDenial) < _denialCooldownSeconds
  }

  private static func captureScreen(maxDimension: Int, quality: Double, result: @escaping FlutterResult) {
    // If already succeeded before, go straight to capture.
    // If in denial cooldown, return error without calling SCKit (no popup).
    if !_screenCaptureEverSucceeded && _isInDenialCooldown {
      result(FlutterError(code: "PERMISSION_DENIED",
                          message: "屏幕录制权限未授予，请在系统设置中授权后会自动恢复",
                          details: nil))
      return
    }

    if #available(macOS 14.0, *) {
      captureWithSCKit(maxDimension: maxDimension, quality: quality, result: result)
    } else {
      result(FlutterError(code: "CAPTURE_FAILED", message: "macOS 14+ required", details: nil))
    }
  }

  @available(macOS 14.0, *)
  private static func captureWithSCKit(maxDimension: Int, quality: Double, result: @escaping FlutterResult) {
    Task { @MainActor in
      do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        // If we get here without error, SCKit permission is granted.
        if !_screenCaptureEverSucceeded {
          NSLog("[RDesk] Screen capture permission confirmed (first success)")
          _screenCaptureEverSucceeded = true
          _lastDenialTime = nil
        }

        let mainID = CGMainDisplayID()
        // Sort displays: main display first, then by displayID
        let sorted = content.displays.sorted { a, b in
          if a.displayID == mainID { return true }
          if b.displayID == mainID { return false }
          return a.displayID < b.displayID
        }
        let idx = min(_selectedDisplayIndex, sorted.count - 1)
        guard let display = sorted.isEmpty ? nil : sorted[max(0, idx)] as SCDisplay? else {
          result(FlutterError(code: "CAPTURE_FAILED", message: "No display found", details: nil))
          return
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        let maxD = CGFloat(maxDimension)
        let dw = CGFloat(display.width)
        let dh = CGFloat(display.height)
        if dw > maxD || dh > maxD {
          let s = min(maxD / dw, maxD / dh)
          config.width = Int(dw * s)
          config.height = Int(dh * s)
        } else {
          config.width = display.width
          config.height = display.height
        }
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let w = image.width
        let h = image.height
        let img = image

        // Encode JPEG in memory and return bytes directly (no disk I/O).
        DispatchQueue.global(qos: .userInitiated).async {
          let mutableData = NSMutableData()
          guard let dest = CGImageDestinationCreateWithData(mutableData as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
            DispatchQueue.main.async { result(FlutterError(code: "CAPTURE_FAILED", message: "JPEG dest fail", details: nil)) }
            return
          }
          CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
          guard CGImageDestinationFinalize(dest) else {
            DispatchQueue.main.async { result(FlutterError(code: "CAPTURE_FAILED", message: "JPEG encode fail", details: nil)) }
            return
          }
          let jpegBytes = FlutterStandardTypedData(bytes: mutableData as Data)
          DispatchQueue.main.async {
            result(["bytes": jpegBytes, "width": w, "height": h])
          }
        }
      } catch {
        let msg = error.localizedDescription
        let isTCC = msg.contains("TCC") || msg.contains("permission") ||
                    msg.contains("denied") || msg.contains("not authorized") ||
                    msg.contains("User declined")
        if isTCC {
          // Start cooldown — won't call SCKit again for _denialCooldownSeconds.
          _lastDenialTime = Date()
          _screenCaptureEverSucceeded = false
          NSLog("[RDesk] Screen recording TCC denied, entering \(_denialCooldownSeconds)s cooldown. Error: \(msg)")
        }
        let code = isTCC ? "PERMISSION_DENIED" : "CAPTURE_FAILED"
        result(FlutterError(code: code, message: "SCKit: \(msg)", details: nil))
      }
    }
  }

  // MARK: Permissions

  private static func currentPermissionState() -> [String: Bool] {
    // On macOS 15+, CGPreflightScreenCaptureAccess() always returns false.
    // Use our own tracking based on actual SCKit success.
    let screenGranted = _screenCaptureEverSucceeded || CGPreflightScreenCaptureAccess()
    return [
      "screenRecordingGranted": screenGranted,
      "accessibilityGranted": AXIsProcessTrusted(),
    ]
  }

  private static func requestPermissionPrompts() {
    // Only prompt once per launch to avoid repeated system dialogs.
    if !_screenPermissionRequested {
      _screenPermissionRequested = true
      _ = CGRequestScreenCaptureAccess()
    }
    if !_accessibilityPermissionRequested {
      _accessibilityPermissionRequested = true
      let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
      _ = AXIsProcessTrustedWithOptions(opts)
    }
  }

  private static func openSystemSettings(anchor: String) {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
    NSWorkspace.shared.open(url)
  }
}
