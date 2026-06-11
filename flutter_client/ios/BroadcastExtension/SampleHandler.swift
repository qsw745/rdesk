import ReplayKit
import CoreMedia
import CoreVideo
import UIKit

/// Broadcast Upload Extension – receives screen frames from ReplayKit
/// and writes them to the shared App Group container for the main app.
class SampleHandler: RPBroadcastSampleHandler {
    private var frameCount: Int = 0
    /// Only process every Nth frame to save CPU/memory (target ~5-8 fps).
    private let frameSkip: Int = 6
    /// Reuse CIContext across frames to avoid expensive re-creation.
    private lazy var ciContext = CIContext(options: [.useSoftwareRenderer: false])

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        frameCount = 0
        // Notify main app that broadcast is now active
        let meta = FrameShared.FrameMeta(
            width: 0, height: 0,
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
            isActive: true
        )
        if let metaURL = FrameShared.metaFileURL,
           let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: metaURL, options: .atomic)
        }
    }

    override func broadcastPaused() {
        // User paused – write inactive
    }

    override func broadcastResumed() {
        // User resumed
    }

    override func broadcastFinished() {
        FrameShared.writeInactive()
        FrameShared.cleanup()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }

        frameCount += 1
        guard frameCount % frameSkip == 0 else { return }

        autoreleasepool {
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }

            let width = CVPixelBufferGetWidth(imageBuffer)
            let height = CVPixelBufferGetHeight(imageBuffer)

            // Scale down for bandwidth: max 960px on longest side
            let maxDimension: CGFloat = 960
            let scale = min(maxDimension / CGFloat(width), maxDimension / CGFloat(height), 1.0)
            let scaledWidth = Int(CGFloat(width) * scale)
            let scaledHeight = Int(CGFloat(height) * scale)

            guard let jpegData = pixelBufferToJPEG(imageBuffer, quality: 0.5,
                                                    targetWidth: scaledWidth,
                                                    targetHeight: scaledHeight)
            else { return }

            FrameShared.writeFrame(jpegData: jpegData, width: scaledWidth, height: scaledHeight)
        }
    }

    /// Convert a CVPixelBuffer to JPEG Data, optionally resizing.
    private func pixelBufferToJPEG(_ pixelBuffer: CVPixelBuffer, quality: CGFloat,
                                    targetWidth: Int, targetHeight: Int) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = ciContext

        // Scale if needed
        let srcWidth = CVPixelBufferGetWidth(pixelBuffer)
        let srcHeight = CVPixelBufferGetHeight(pixelBuffer)
        let scaleX = CGFloat(targetWidth) / CGFloat(srcWidth)
        let scaleY = CGFloat(targetHeight) / CGFloat(srcHeight)

        let transformed: CIImage
        if abs(scaleX - 1.0) > 0.01 || abs(scaleY - 1.0) > 0.01 {
            transformed = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        } else {
            transformed = ciImage
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let jpegData = context.jpegRepresentation(
            of: transformed,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
        ) else { return nil }

        return jpegData
    }
}
