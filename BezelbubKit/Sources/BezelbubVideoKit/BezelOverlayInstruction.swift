import AVFoundation
import CoreImage

/// Carries all compositing data for a single time range in our custom video compositor.
/// Used on iOS where `AVVideoCompositionCoreAnimationTool` doesn't properly composite
/// CALayer alpha transparency.
final class BezelOverlayInstruction: NSObject, @unchecked Sendable, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let sourceTrackID: CMPersistentTrackID
    let bezelImage: CIImage
    let maskImage: CIImage?
    let videoTransform: CGAffineTransform
    let backgroundColor: CIImage
    let renderSize: CGSize

    init(
        timeRange: CMTimeRange,
        sourceTrackID: CMPersistentTrackID,
        bezelImage: CIImage,
        maskImage: CIImage?,
        videoTransform: CGAffineTransform,
        backgroundColor: CIImage,
        renderSize: CGSize
    ) {
        self.timeRange = timeRange
        self.sourceTrackID = sourceTrackID
        self.bezelImage = bezelImage
        self.maskImage = maskImage
        self.videoTransform = videoTransform
        self.backgroundColor = backgroundColor
        self.renderSize = renderSize
        self.requiredSourceTrackIDs = [NSNumber(value: Int(sourceTrackID))]
        super.init()
    }
}
