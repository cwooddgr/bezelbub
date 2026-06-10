import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal

/// Custom `AVVideoCompositing` implementation for iOS video export.
///
/// `AVVideoCompositionCoreAnimationTool` does not properly composite CALayer alpha
/// transparency on iOS, resulting in a black screen area. This compositor manually
/// composites each frame using Core Image:
///   1. Transform the source video frame into the screen region
///   2. Apply the precomputed screen mask (rounded corners)
///   3. Layer: background color → masked video → bezel overlay
final class BezelOverlayCompositor: NSObject, AVVideoCompositing {

    // MARK: - Protocol requirements

    var sourcePixelBufferAttributes: [String: Any]? {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    private var renderContext: AVVideoCompositionRenderContext?
    private let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        }
        return CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    }()

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContext = newRenderContext
    }

    func cancelAllPendingVideoCompositionRequests() {
        // Stateless — nothing to cancel
    }

    // MARK: - Frame compositing

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? BezelOverlayInstruction,
              let sourceBuffer = request.sourceFrame(byTrackID: instruction.sourceTrackID)
        else {
            request.finish(with: NSError(domain: "BezelOverlayCompositor", code: -1))
            return
        }

        let renderSize = instruction.renderSize
        let renderW = renderSize.width
        let renderH = renderSize.height

        // Source video frame as CIImage
        let sourceImage = CIImage(cvPixelBuffer: sourceBuffer)

        // The videoTransform is in top-left-origin coordinates (matching CALayer / AVFoundation).
        // CIImage uses bottom-left origin, so we conjugate the transform with Y-flips.
        // The source-side flip converts source coords (bottom-left → top-left) using the source height,
        // while the output-side flip converts back (top-left → bottom-left) using the render height.
        let sourceH = sourceImage.extent.height
        let flipSrc = CGAffineTransform(scaleX: 1, y: -1)
            .concatenating(CGAffineTransform(translationX: 0, y: sourceH))
        let flipOut = CGAffineTransform(scaleX: 1, y: -1)
            .concatenating(CGAffineTransform(translationX: 0, y: renderH))

        let ciTransform = flipSrc
            .concatenating(instruction.videoTransform)
            .concatenating(flipOut)

        let transformedVideo = sourceImage.transformed(by: ciTransform)

        // Apply screen mask if available
        let maskedVideo: CIImage
        if let maskImage = instruction.maskImage {
            // Scale mask to render size
            let maskW = maskImage.extent.width
            let maskH = maskImage.extent.height
            let scaledMask = maskImage.transformed(by: CGAffineTransform(
                scaleX: renderW / maskW,
                y: renderH / maskH
            ))

            // Use a transparent background with the same extent as the render size.
            // CIImage.empty() has zero extent, which causes CIBlendWithMask to produce
            // a zero-extent output — resulting in no video content in the final composite.
            let clearBg = CIImage(color: .clear)
                .cropped(to: CGRect(origin: .zero, size: renderSize))

            let blendFilter = CIFilter.blendWithMask()
            blendFilter.inputImage = transformedVideo
            blendFilter.backgroundImage = clearBg
            blendFilter.maskImage = scaledMask
            maskedVideo = blendFilter.outputImage ?? transformedVideo
        } else {
            maskedVideo = transformedVideo
        }

        // Composite layers: background → masked video → bezel
        let background = instruction.backgroundColor
        let bezel = instruction.bezelImage

        let videoOverBg = maskedVideo.composited(over: background)
        let final = bezel.composited(over: videoOverBg)

        // Render to output pixel buffer
        guard let outputBuffer = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "BezelOverlayCompositor", code: -2))
            return
        }

        let renderRect = CGRect(origin: .zero, size: renderSize)
        ciContext.render(final, to: outputBuffer, bounds: renderRect, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)

        request.finish(withComposedVideoFrame: outputBuffer)
    }
}
