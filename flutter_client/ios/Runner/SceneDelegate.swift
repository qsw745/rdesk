import Flutter
import UIKit
import ReplayKit

class SceneDelegate: FlutterSceneDelegate {
  private let hostChannelName = "com.qsw.rdesk/android_host"
  private let extensionBundleID = "com.qsw.rdesk.BroadcastExtension"

  /// Cached broadcast picker (hidden, used to programmatically trigger the system sheet).
  private var broadcastPicker: RPSystemBroadcastPickerView?

  /// Whether the user has started a broadcast via the picker.
  private var isBroadcasting = false

  /// Last frame timestamp we returned to Flutter — avoids redundant JPEG file reads.
  private var lastReadTimestampMs: Int64 = 0

  // MARK: - Scene Lifecycle

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    // FlutterSceneDelegate creates the engine and FlutterViewController here.
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    // After super, the window and FlutterViewController are guaranteed to exist.
    guard let windowScene = scene as? UIWindowScene,
          let window = windowScene.windows.first,
          let controller = window.rootViewController as? FlutterViewController
    else { return }

    setupHostChannel(messenger: controller.binaryMessenger)
  }

  // MARK: - Method Channel

  private func setupHostChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: hostChannelName,
      binaryMessenger: messenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "getScreenCaptureState":
        result(self.getScreenCaptureState())
      case "requestScreenCapturePermission":
        // ReplayKit permission is requested at broadcast start via system picker.
        result(self.getScreenCaptureState())
      case "startScreenCaptureService":
        self.startBroadcast(result: result)
      case "stopScreenCaptureService":
        self.stopBroadcast(result: result)
      case "getLatestCapturedFrame":
        result(self.getLatestFrame())
      case "showRemoteTapIndicator":
        // No accessibility overlay on iOS
        result(true)
      case "performRemoteLongPress", "performRemoteDrag", "performRemoteTextInput",
           "performRemoteAction", "wakeScreen", "setKeepScreenOn":
        // Input simulation not available on iOS (sandbox restrictions)
        result(false)
      case "setClipboardText":
        if let args = call.arguments as? [String: String],
           let text = args["text"] {
          UIPasteboard.general.string = text
          result(true)
        } else {
          result(false)
        }
      case "getClipboardText":
        result(UIPasteboard.general.string)
      case "openAccessibilitySettings", "openOverlaySettings",
           "openNotificationSettings", "openBatteryOptimizationSettings",
           "openAppDetailsSettings":
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Screen Capture State

  private func getScreenCaptureState() -> [String: Any] {
    let meta = FrameShared.readMeta()
    let isActive = meta?.isActive == true
    let isRunning = isBroadcasting && isActive

    return [
      "state": isRunning ? "running" : "idle",
      "hasPermission": true,
      "isRunning": isRunning,
      "accessibilityEnabled": true,   // Always true on iOS (not applicable)
      "overlayEnabled": true,
      "notificationsEnabled": true,
      "batteryOptimizationIgnored": true,
      "manufacturer": "apple",
    ]
  }

  // MARK: - Broadcast Control

  private func startBroadcast(result: @escaping FlutterResult) {
    isBroadcasting = true
    lastReadTimestampMs = 0

    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.showBroadcastPicker()

      // Return isRunning=true immediately so Flutter starts preview polling.
      // Frames will arrive once the user confirms in the system broadcast picker.
      var state = self.getScreenCaptureState()
      state["isRunning"] = true
      state["state"] = "running"
      result(state)
    }
  }

  private func stopBroadcast(result: @escaping FlutterResult) {
    isBroadcasting = false
    lastReadTimestampMs = 0
    FrameShared.writeInactive()
    result(getScreenCaptureState())
  }

  /// Shows the system broadcast picker sheet.
  private func showBroadcastPicker() {
    if broadcastPicker == nil {
      let picker = RPSystemBroadcastPickerView(
        frame: CGRect(x: 0, y: 0, width: 44, height: 44)
      )
      picker.preferredExtension = extensionBundleID
      picker.showsMicrophoneButton = false
      broadcastPicker = picker
    }

    // Programmatically tap the hidden picker button to show the system sheet
    guard let picker = broadcastPicker else { return }
    for subview in picker.subviews {
      if let button = subview as? UIButton {
        button.sendActions(for: .touchUpInside)
        break
      }
    }
  }

  // MARK: - Frame Reading

  private func getLatestFrame() -> [String: Any]? {
    // Read meta first (small JSON) to check for new frames without loading JPEG
    guard let meta = FrameShared.readMeta(),
          meta.isActive,
          meta.width > 0
    else { return nil }

    // Skip if same frame as last read
    guard meta.timestampMs > lastReadTimestampMs else { return nil }

    // Check frame freshness (reject frames older than 5 seconds)
    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
    guard nowMs - meta.timestampMs < 5000 else { return nil }

    // Now read the actual JPEG data
    guard let frameURL = FrameShared.frameFileURL,
          let jpegData = try? Data(contentsOf: frameURL),
          !jpegData.isEmpty
    else { return nil }

    lastReadTimestampMs = meta.timestampMs

    return [
      "bytes": FlutterStandardTypedData(bytes: jpegData),
      "width": meta.width,
      "height": meta.height,
      "timestampMs": meta.timestampMs,
    ]
  }
}
