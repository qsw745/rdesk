import Foundation
import CoreGraphics

/// Shared constants and helpers used by both the main app and the
/// Broadcast Upload Extension to exchange captured screen frames via App Group.
enum FrameShared {
    /// App Group identifier – must be enabled in both targets' entitlements.
    static let appGroupID = "group.com.qsw.rdesk"

    /// File name for the latest JPEG frame inside the shared container.
    static let frameFileName = "latest_frame.jpg"

    /// File name for the metadata JSON.
    static let metaFileName = "frame_meta.json"

    /// Darwin notification name posted by the extension when a new frame is written.
    static let newFrameNotification = "com.qsw.rdesk.newFrame" as CFString
    private static let maxDimensionKey = "capture.maxDimension"
    private static let jpegQualityKey = "capture.jpegQuality"
    private static let frameSkipKey = "capture.frameSkip"

    struct CaptureSettings {
        let maxDimension: CGFloat
        let jpegQuality: CGFloat
        let frameSkip: Int
    }

    // MARK: - Paths

    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var frameFileURL: URL? {
        sharedContainerURL?.appendingPathComponent(frameFileName)
    }

    static var metaFileURL: URL? {
        sharedContainerURL?.appendingPathComponent(metaFileName)
    }

    static func writeCaptureSettings(quality: Double, fps: Int?) {
        let clampedQuality = min(max(quality, 0.1), 1.0)
        let maxDimension: Double
        let jpegQuality: Double
        let maxFps: Int
        if clampedQuality >= 0.85 {
            maxDimension = 1920
            jpegQuality = 0.85
            maxFps = 15
        } else if clampedQuality <= 0.55 {
            maxDimension = 960
            jpegQuality = 0.55
            maxFps = 10
        } else {
            maxDimension = 1440
            jpegQuality = 0.75
            maxFps = 12
        }
        let targetFps = min(max(fps ?? maxFps, 5), maxFps)
        let frameSkip = max(1, Int((30.0 / Double(targetFps)).rounded()))
        let defaults = UserDefaults(suiteName: appGroupID)
        defaults?.set(maxDimension, forKey: maxDimensionKey)
        defaults?.set(jpegQuality, forKey: jpegQualityKey)
        defaults?.set(frameSkip, forKey: frameSkipKey)
    }

    static func readCaptureSettings() -> CaptureSettings {
        let defaults = UserDefaults(suiteName: appGroupID)
        let maxDimension = defaults?.double(forKey: maxDimensionKey) ?? 1440
        let jpegQuality = defaults?.double(forKey: jpegQualityKey) ?? 0.75
        let frameSkip = defaults?.integer(forKey: frameSkipKey) ?? 3
        return CaptureSettings(
            maxDimension: CGFloat(maxDimension > 0 ? maxDimension : 1440),
            jpegQuality: CGFloat(jpegQuality > 0 ? jpegQuality : 0.75),
            frameSkip: max(1, frameSkip)
        )
    }

    // MARK: - Write (Extension side)

    struct FrameMeta: Codable {
        let width: Int
        let height: Int
        let timestampMs: Int64
        let isActive: Bool
    }

    static func writeFrame(jpegData: Data, width: Int, height: Int) {
        guard let frameURL = frameFileURL, let metaURL = metaFileURL else { return }

        let meta = FrameMeta(
            width: width,
            height: height,
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
            isActive: true
        )

        // Write JPEG first, then metadata (readers check meta timestamp)
        try? jpegData.write(to: frameURL, options: .atomic)
        if let metaData = try? JSONEncoder().encode(meta) {
            try? metaData.write(to: metaURL, options: .atomic)
        }

        // Notify main app via Darwin notification
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName(newFrameNotification), nil, nil, true)
    }

    static func writeInactive() {
        guard let metaURL = metaFileURL else { return }
        let meta = FrameMeta(width: 0, height: 0, timestampMs: 0, isActive: false)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: metaURL, options: .atomic)
        }
    }

    // MARK: - Read (Main app side)

    static func readMeta() -> FrameMeta? {
        guard let metaURL = metaFileURL,
              let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(FrameMeta.self, from: data)
        else { return nil }
        return meta
    }

    static func readFrame() -> (data: Data, meta: FrameMeta)? {
        guard let meta = readMeta(), meta.isActive, meta.width > 0 else { return nil }

        // Check frame freshness (reject frames older than 5 seconds)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        guard nowMs - meta.timestampMs < 5000 else { return nil }

        guard let frameURL = frameFileURL,
              let jpegData = try? Data(contentsOf: frameURL),
              !jpegData.isEmpty
        else { return nil }

        return (jpegData, meta)
    }

    /// Clean up shared frame files.
    static func cleanup() {
        if let url = frameFileURL { try? FileManager.default.removeItem(at: url) }
        if let url = metaFileURL { try? FileManager.default.removeItem(at: url) }
    }
}
