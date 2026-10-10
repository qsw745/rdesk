import Cocoa
import FlutterMacOS
import ApplicationServices
import CoreGraphics
import ScreenCaptureKit
import ServiceManagement

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Register desktop host channel with binary messenger.
    DesktopHostPlugin.register(with: flutterViewController.engine.binaryMessenger)
    LoginItemPlugin.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

// MARK: - DesktopHostPlugin

/// Handles desktop host MethodChannel: screen capture (ScreenCaptureKit),
/// permissions, and remote input (CGEvent).
class DesktopHostPlugin {
  private static let channelName = "com.qsw.rdesk/desktop_host"
  /// Currently selected display index (0 = main display).
  private static var _selectedDisplayIndex = 0
  /// The display capture last resolved that index to. Remote coordinates are
  /// normalized to the captured frame, so input targets this display instead
  /// of resolving the index a second time against a different display list.
  private static var _capturedDisplayID: CGDirectDisplayID?

  // Capture intent is separate from host availability. All lifecycle state is
  // owned by the main actor / Flutter platform thread.
  private static var _captureEnabled = false
  private static var _captureGeneration = 0
  private static var _captureRequestID = 0
  private static var _captureTask: Task<Void, Never>?
  private static var _pendingCaptureResult: FlutterResult?
  private static var _captureRequests = 0
  private static var _encodedFrames = 0

  /// Migrate away from the retired CLI capture path. Only remove our own
  /// regular temporary file; never follow a symlink or inspect its image.
  private static func clearLegacyScreenshot() {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("rdesk_desktop_frame.jpg")
    let manager = FileManager.default
    guard let attributes = try? manager.attributesOfItem(atPath: url.path),
          attributes[.type] as? FileAttributeType == .typeRegular else { return }
    do {
      try manager.removeItem(at: url)
      NSLog("[RDeskCapture] retired CLI frame removed")
    } catch {
      NSLog("[RDeskCapture] retired CLI frame cleanup failed: \(error)")
    }
  }

  private static func cancelCapture() {
    _captureRequestID += 1
    _captureTask?.cancel()
    _captureTask = nil
    let pending = _pendingCaptureResult
    _pendingCaptureResult = nil
    pending?(nil)
  }

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

  // MARK: Remote input state

  /// Injected input runs here, in arrival order. Gestures and text pause
  /// between events, which must not stall the platform thread, and a later key
  /// press must not overtake text that is still being typed.
  private static let _inputQueue = DispatchQueue(
    label: "com.qsw.rdesk.desktop_host.input", qos: .userInteractive)

  private static let _pointerSettleInterval: TimeInterval = 0.02
  private static let _clickHoldInterval: TimeInterval = 0.05
  private static let _dragSteps = 10
  private static let _dragStepInterval: TimeInterval = 0.02
  private static let _textStrokeInterval: TimeInterval = 0.002

  private enum MouseAction {
    case click(CGPoint)
    case rightClick(CGPoint)
    case drag(from: CGPoint, to: CGPoint)
    case scroll(lines: Int32)
  }

  static func register(with messenger: FlutterBinaryMessenger) {
    clearLegacyScreenshot()
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
      case "setCaptureEnabled":
        let args = call.arguments as? [String: Any]
        let generation = args?["generation"] as? Int ?? 0
        guard generation >= _captureGeneration else { result(nil); return }
        cancelCapture()
        _captureGeneration = generation
        _captureEnabled = args?["enabled"] as? Bool ?? false
        if !_captureEnabled { clearLegacyScreenshot() }
        NSLog("[RDeskCapture] enabled=\(_captureEnabled) generation=\(generation) requests=\(_captureRequests) encoded=\(_encodedFrames)")
        result(nil)
      case "captureDiagnostics":
        result(["enabled": _captureEnabled, "pending": _captureTask != nil,
                "requests": _captureRequests, "encoded": _encodedFrames])
      case "captureScreen":
        let args = call.arguments as? [String: Any]
        guard _captureEnabled, args?["generation"] as? Int == _captureGeneration else {
          result(nil)
          return
        }
        let maxDim = args?["maxDimension"] as? Int ?? 1920
        let quality = args?["quality"] as? Double ?? 0.5
        captureScreen(maxDimension: maxDim, quality: quality, result: result)
      case "listDisplays":
        listDisplays(result: result)
      case "switchDisplay":
        let args = call.arguments as? [String: Any]
        let index = args?["index"] as? Int ?? 0
        _selectedDisplayIndex = index
        _capturedDisplayID = nil
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
      case "performKeyPress":
        guard
          let args = call.arguments as? [String: Any],
          let keyCode = args["keyCode"] as? Int
        else {
          result(false)
          return
        }
        let modifiers = args["modifiers"] as? [String] ?? []
        runInput(result) { performKeyPress(keyCode: keyCode, modifiers: modifiers) }
      case "performMouse":
        guard
          let args = call.arguments as? [String: Any],
          let action = mouseAction(from: args)
        else {
          NSLog("[RDesk] performMouse rejected: invalid arguments")
          result(false)
          return
        }
        runInput(result) { performMouse(action) }
      case "performTextInput":
        guard
          let args = call.arguments as? [String: Any],
          let text = args["text"] as? String
        else {
          result(false)
          return
        }
        runInput(result) { performTextInput(text) }
      case "launchMissionControlAction":
        guard
          let args = call.arguments as? [String: Any],
          let action = args["action"] as? String
        else {
          result(false)
          return
        }
        result(launchMissionControlAction(action))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Runs `work` on the input queue and answers on the platform thread.
  private static func runInput(_ result: @escaping FlutterResult, _ work: @escaping () -> Bool) {
    _inputQueue.async {
      let ok = work()
      DispatchQueue.main.async { result(ok) }
    }
  }

  /// Posts a keyboard event from the signed RDesk process itself.
  ///
  /// Spawning Python/Quartz for keyboard actions makes macOS evaluate the
  /// untrusted child executable instead of the RDesk accessibility grant. The
  /// child can exit successfully while TCC silently drops every event.
  private static func performKeyPress(keyCode: Int, modifiers: [String]) -> Bool {
    let accessibilityTrusted = AXIsProcessTrusted()
    NSLog(
      "[RDesk] performKeyPress requested: keyCode=\(keyCode) " +
      "modifiers=\(modifiers) accessibilityTrusted=\(accessibilityTrusted)"
    )
    guard accessibilityTrusted else {
      NSLog("[RDesk] performKeyPress blocked: accessibility permission missing")
      return false
    }
    guard
      let source = CGEventSource(stateID: .hidSystemState),
      let keyDown = CGEvent(
        keyboardEventSource: source,
        virtualKey: CGKeyCode(keyCode),
        keyDown: true
      ),
      let keyUp = CGEvent(
        keyboardEventSource: source,
        virtualKey: CGKeyCode(keyCode),
        keyDown: false
      )
    else {
      return false
    }

    var flags = CGEventFlags()
    for modifier in modifiers {
      switch modifier {
      case "command":
        flags.insert(.maskCommand)
      case "control":
        flags.insert(.maskControl)
      case "option":
        flags.insert(.maskAlternate)
      case "shift":
        flags.insert(.maskShift)
      default:
        NSLog("[RDesk] performKeyPress ignored modifier: \(modifier)")
      }
    }

    keyDown.flags = flags
    keyUp.flags = flags
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
    NSLog("[RDesk] performKeyPress posted: keyCode=\(keyCode) flags=\(flags.rawValue)")
    return true
  }

  // MARK: Mouse and text input

  /// Resolves a `performMouse` call against the display the viewer is looking
  /// at. Must run on the platform thread, which owns the display selection.
  private static func mouseAction(from args: [String: Any]) -> MouseAction? {
    func point(_ xKey: String, _ yKey: String) -> CGPoint? {
      guard
        let x = (args[xKey] as? NSNumber)?.doubleValue,
        let y = (args[yKey] as? NSNumber)?.doubleValue,
        let display = inputDisplayID()
      else {
        return nil
      }
      return DesktopInputMapping.globalPoint(
        normalizedX: x, normalizedY: y, in: CGDisplayBounds(display))
    }

    switch args["kind"] as? String {
    case "click":
      return point("x", "y").map { .click($0) }
    case "rightClick":
      return point("x", "y").map { .rightClick($0) }
    case "drag":
      guard let start = point("startX", "startY"), let end = point("endX", "endY") else {
        return nil
      }
      return .drag(from: start, to: end)
    case "scroll":
      guard let lines = (args["deltaY"] as? NSNumber)?.intValue else { return nil }
      return .scroll(lines: Int32(clamping: lines))
    default:
      return nil
    }
  }

  /// The display remote pointer coordinates refer to: the one being captured,
  /// or the selected index when nothing has been captured since the last switch.
  private static func inputDisplayID() -> CGDirectDisplayID? {
    if let captured = _capturedDisplayID, CGDisplayIsOnline(captured) != 0 {
      return captured
    }
    return DesktopInputMapping.display(at: _selectedDisplayIndex, in: orderedDisplayIDs())
  }

  /// Posts pointer events from the signed RDesk process, for the same TCC
  /// attribution reason as `performKeyPress`.
  private static func performMouse(_ action: MouseAction) -> Bool {
    guard AXIsProcessTrusted() else {
      NSLog("[RDesk] performMouse blocked: accessibility permission missing")
      return false
    }
    guard let source = CGEventSource(stateID: .hidSystemState) else { return false }

    let posted: Bool
    switch action {
    case .click(let point):
      posted = click(at: point, button: .left, source: source)
    case .rightClick(let point):
      posted = click(at: point, button: .right, source: source)
    case .drag(let start, let end):
      posted = drag(from: start, to: end, source: source)
    case .scroll(let lines):
      posted = scroll(lines: lines, source: source)
    }
    NSLog("[RDesk] performMouse \(posted ? "posted" : "failed"): \(action)")
    return posted
  }

  private static func scroll(lines: Int32, source: CGEventSource) -> Bool {
    guard
      let event = CGEvent(
        scrollWheelEvent2Source: source, units: .line,
        wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)
    else {
      return false
    }
    event.post(tap: .cghidEventTap)
    return true
  }

  private static func postMouse(
    _ type: CGEventType, at point: CGPoint, button: CGMouseButton, source: CGEventSource
  ) -> Bool {
    guard
      let event = CGEvent(
        mouseEventSource: source, mouseType: type,
        mouseCursorPosition: point, mouseButton: button)
    else {
      return false
    }
    event.post(tap: .cghidEventTap)
    return true
  }

  private static func click(at point: CGPoint, button: CGMouseButton, source: CGEventSource) -> Bool {
    let isRight = button == .right
    guard postMouse(.mouseMoved, at: point, button: .left, source: source) else { return false }
    Thread.sleep(forTimeInterval: _pointerSettleInterval)
    guard
      postMouse(isRight ? .rightMouseDown : .leftMouseDown, at: point, button: button, source: source)
    else {
      return false
    }
    Thread.sleep(forTimeInterval: _clickHoldInterval)
    return postMouse(isRight ? .rightMouseUp : .leftMouseUp, at: point, button: button, source: source)
  }

  private static func drag(from start: CGPoint, to end: CGPoint, source: CGEventSource) -> Bool {
    guard postMouse(.mouseMoved, at: start, button: .left, source: source) else { return false }
    Thread.sleep(forTimeInterval: _pointerSettleInterval)
    guard postMouse(.leftMouseDown, at: start, button: .left, source: source) else { return false }

    var moved = true
    for point in DesktopInputMapping.dragPath(from: start, to: end, steps: _dragSteps) {
      guard postMouse(.leftMouseDragged, at: point, button: .left, source: source) else {
        moved = false
        break
      }
      Thread.sleep(forTimeInterval: _dragStepInterval)
    }
    // Release even after a failed step so the remote button is never left held.
    return postMouse(.leftMouseUp, at: end, button: .left, source: source) && moved
  }

  /// Types text as Unicode key events, independent of the host keyboard
  /// layout. The text itself is never logged.
  private static func performTextInput(_ text: String) -> Bool {
    guard AXIsProcessTrusted() else {
      NSLog("[RDesk] performTextInput blocked: accessibility permission missing")
      return false
    }
    guard let source = CGEventSource(stateID: .hidSystemState) else { return false }

    let strokes = DesktopInputMapping.textStrokes(for: text)
    for stroke in strokes {
      guard postTextStroke(stroke, source: source) else { return false }
      Thread.sleep(forTimeInterval: _textStrokeInterval)
    }
    NSLog("[RDesk] performTextInput posted: strokes=\(strokes.count)")
    return true
  }

  private static func postTextStroke(
    _ stroke: DesktopInputMapping.TextStroke, source: CGEventSource
  ) -> Bool {
    let keyCode: CGKeyCode
    let units: [UInt16]
    switch stroke {
    case .key(let code):
      keyCode = code
      units = []
    case .unicode(let value):
      keyCode = 0
      units = value
    }
    guard
      let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    else {
      return false
    }
    for event in [keyDown, keyUp] {
      // A modifier held on the host keyboard must not turn text into shortcuts.
      event.flags = []
      if !units.isEmpty {
        event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
      }
      event.post(tap: .cghidEventTap)
    }
    return true
  }

  /// Launches macOS' own Mission Control helper with the action argument used
  /// by the installed system app. This is independent of configurable keyboard
  /// shortcuts and runs from RDesk's active Aqua session.
  private static func launchMissionControlAction(_ action: String) -> Bool {
    let argument: String
    switch action {
    case "show_all_windows":
      argument = "0"
    case "show_desktop":
      argument = "1"
    default:
      return false
    }

    let executablePath = "/usr/bin/open"
    guard FileManager.default.isExecutableFile(atPath: executablePath) else {
      NSLog("[RDesk] LaunchServices helper missing: \(executablePath)")
      return false
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = [
      "-b", "com.apple.exposelauncher", "--args", argument,
    ]
    do {
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        NSLog(
          "[RDesk] launchMissionControlAction rejected: " +
          "action=\(action) status=\(process.terminationStatus)"
        )
        return false
      }
      NSLog(
        "[RDesk] launchMissionControlAction accepted: " +
        "action=\(action) argument=\(argument)"
      )
      return true
    } catch {
      NSLog("[RDesk] launchMissionControlAction failed: \(error)")
      return false
    }
  }

  // MARK: Display listing (CG-based, no TCC prompt)

  /// Online displays, main display first, then by displayID. `switchDisplay`
  /// indexes into this order.
  private static func orderedDisplayIDs() -> [CGDirectDisplayID] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 10)
    var count: UInt32 = 0
    CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count)
    return DesktopInputMapping.orderedDisplays(Array(ids.prefix(Int(count))), main: CGMainDisplayID())
  }

  /// What each screen calls itself ("VG27AQL3A", "Built-in Retina Display"),
  /// by display ID. Mirrored screens are not listed by AppKit and get none.
  private static func displayModelNames() -> [CGDirectDisplayID: String] {
    var names: [CGDirectDisplayID: String] = [:]
    for screen in NSScreen.screens {
      let key = NSDeviceDescriptionKey("NSScreenNumber")
      guard let number = screen.deviceDescription[key] as? NSNumber else { continue }
      let name = screen.localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
      if !name.isEmpty { names[number.uint32Value] = name }
    }
    return names
  }

  /// List displays using CoreGraphics — never triggers a permission prompt.
  private static func listDisplays(result: @escaping FlutterResult) {
    let mainID = CGMainDisplayID()
    let models = displayModelNames()
    let ordered = orderedDisplayIDs()
    // The selection outlives a viewer's session: the next viewer has to be
    // told which screen it is looking at.
    let selected = max(0, min(_selectedDisplayIndex, ordered.count - 1))
    let list = ordered.enumerated().map { (i, id) -> [String: Any] in
      let bounds = CGDisplayBounds(id)
      let width = Int(bounds.width)
      let height = Int(bounds.height)
      var entry: [String: Any] = [
        "index": i,
        // Older viewers show this text as it is; newer ones build their own
        // label from the fields below.
        "name": "显示屏 \(i + 1)（\(models[id] ?? "\(width)×\(height)")）",
        "width": width,
        "height": height,
        "isMain": id == mainID,
        "selected": i == selected,
      ]
      if let model = models[id] { entry["model"] = model }
      return entry
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

    guard _captureEnabled, _captureTask == nil else { result(nil); return }
    if #available(macOS 14.0, *) {
      _pendingCaptureResult = result
      _captureRequestID += 1
      let requestID = _captureRequestID
      captureWithSCKit(maxDimension: maxDimension, quality: quality, result: { value in
        guard requestID == _captureRequestID else { return }
        let pending = _pendingCaptureResult
        _pendingCaptureResult = nil
        _captureTask = nil
        pending?(value)
      })
    } else {
      result(FlutterError(code: "CAPTURE_FAILED", message: "macOS 14+ required", details: nil))
    }
  }

  @available(macOS 14.0, *)
  private static func captureWithSCKit(maxDimension: Int, quality: Double, result: @escaping FlutterResult) {
    let generation = _captureGeneration
    _captureTask = Task { @MainActor in
      do {
        try Task.checkCancellation()
        guard _captureEnabled, generation == _captureGeneration else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        try Task.checkCancellation()
        guard _captureEnabled, generation == _captureGeneration else { return }

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
        _capturedDisplayID = display.displayID
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

        _captureRequests += 1
        if _captureRequests == 1 || _captureRequests % 50 == 0 {
          NSLog("[RDeskCapture] screenshot request=\(_captureRequests) generation=\(generation)")
        }
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        try Task.checkCancellation()
        guard _captureEnabled, generation == _captureGeneration else { return }
        let w = image.width
        let h = image.height
        let img = image

        // Encoding and stop are serialized on the main actor: after a stop
        // acknowledgement, an old screenshot cannot start encoding or return.
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(mutableData as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
          result(FlutterError(code: "CAPTURE_FAILED", message: "JPEG dest fail", details: nil))
          return
        }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
          result(FlutterError(code: "CAPTURE_FAILED", message: "JPEG encode fail", details: nil))
          return
        }
        _encodedFrames += 1
        result(["bytes": FlutterStandardTypedData(bytes: mutableData as Data), "width": w, "height": h])
      } catch {
        guard !Task.isCancelled, _captureEnabled, generation == _captureGeneration else { return }
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

// MARK: - LoginItemPlugin

/// Lets a home Mac that relays wake requests start RDesk again after a restart.
/// Only the user's explicit switch registers or removes the login item.
class LoginItemPlugin {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.qsw.rdesk/login_item", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard #available(macOS 13.0, *) else {
        result(call.method == "status" || call.method == "set"
          ? ["supported": false, "enabled": false, "requiresApproval": false]
          : FlutterMethodNotImplemented)
        return
      }
      let service = SMAppService.mainApp
      switch call.method {
      case "status":
        result(state(service))
      case "set":
        do {
          if call.arguments as? Bool == true {
            if service.status != .enabled { try service.register() }
          } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
          }
          result(state(service))
        } catch {
          NSLog("[RDesk] login item change failed: \(error.localizedDescription)")
          result(FlutterError(code: "login_item_failed",
                              message: "无法更改登录项，请在系统设置 → 通用 → 登录项中调整",
                              details: nil))
        }
      case "openSettings":
        SMAppService.openSystemSettingsLoginItems()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  @available(macOS 13.0, *)
  private static func state(_ service: SMAppService) -> [String: Bool] {
    ["supported": true,
     "enabled": service.status == .enabled,
     "requiresApproval": service.status == .requiresApproval]
  }
}
