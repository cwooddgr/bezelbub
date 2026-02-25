import AVFoundation
import CoreGraphics
import ImageIO
import QuartzCore

enum VideoFrameCompositor {

    /// Returns the actual pixel dimensions of the video after applying its preferred transform.
    static func videoDimensions(asset: AVAsset) async throws -> (width: Int, height: Int) {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoExportError.noVideoTrack
        }

        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let transformed = size.applying(transform)
        return (width: Int(abs(transformed.width)), height: Int(abs(transformed.height)))
    }

    /// Extracts the first frame of the video as a CGImage for preview.
    static func firstFrame(asset: AVAsset) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        let (image, _) = try await generator.image(at: .zero)
        return image
    }

    /// Rotates a CGImage by the given number of degrees (must be a multiple of 90).
    static func rotateImage(_ image: CGImage, byDegrees degrees: Int) -> CGImage? {
        let radians = CGFloat(degrees) * .pi / 180.0
        let swapped = degrees == 90 || degrees == 270
        let newWidth = swapped ? image.height : image.width
        let newHeight = swapped ? image.width : image.height

        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: newWidth, height: newHeight,
                  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        ctx.translateBy(x: CGFloat(newWidth) / 2, y: CGFloat(newHeight) / 2)
        ctx.rotate(by: -radians) // CG coordinates: positive = CCW, so negate for CW
        ctx.translateBy(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        return ctx.makeImage()
    }

    /// Exports the video with the device bezel overlaid, preserving audio.
    static func export(
        asset: AVAsset,
        device: DeviceDefinition,
        color: DeviceColor,
        isLandscape: Bool,
        extraRotation: Int = 0,
        backgroundColor: CGColor,
        outputURL: URL,
        outputSize: CGSize? = nil,
        progressHandler: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws {
        // --- Load bezel image ---
        let bezelFileName = device.bezelFileName(color: color, landscape: isLandscape)
        guard let bezelURL = ScreenRegionDetector.bezelURL(fileName: bezelFileName),
              let bezelSource = CGImageSourceCreateWithURL(bezelURL as CFURL, nil),
              let bezelImage = CGImageSourceCreateImageAtIndex(bezelSource, 0, nil)
        else {
            throw VideoExportError.bezelNotFound
        }

        let bezelWidth = bezelImage.width
        let bezelHeight = bezelImage.height

        // --- Detect screen region ---
        let screenRegion: CGRect
        if isLandscape {
            let landscapeBezelFileName = device.bezelFileName(color: color, landscape: true)
            if let landscapeRegion = ScreenRegionDetector.screenRegion(forBezelFileName: landscapeBezelFileName) {
                screenRegion = landscapeRegion
            } else if let portraitRegion = device.screenRegion {
                screenRegion = CGRect(
                    x: portraitRegion.origin.y,
                    y: portraitRegion.origin.x,
                    width: portraitRegion.height,
                    height: portraitRegion.width
                )
            } else {
                throw VideoExportError.screenRegionNotFound
            }
        } else {
            guard let portraitRegion = device.screenRegion else {
                throw VideoExportError.screenRegionNotFound
            }
            screenRegion = portraitRegion
        }

        // --- Load video track ---
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoExportError.noVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let duration = try await asset.load(.duration)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)

        // --- Build AVMutableComposition ---
        let composition = AVMutableComposition()

        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoExportError.compositionFailed
        }

        let timeRange = CMTimeRange(start: .zero, duration: duration)
        try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)

        // Copy audio tracks
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        for audioTrack in audioTracks {
            if let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) {
                try compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
            }
        }

        // --- Compute output scaling ---
        let scale: CGFloat
        let renderSize: CGSize
        let scaledScreenRegion: CGRect

        if let outputSize, outputSize.width > 0, outputSize.height > 0 {
            scale = outputSize.width / CGFloat(bezelWidth)
            renderSize = outputSize
            scaledScreenRegion = CGRect(
                x: screenRegion.origin.x * scale,
                y: screenRegion.origin.y * scale,
                width: screenRegion.width * scale,
                height: screenRegion.height * scale
            )
        } else {
            scale = 1.0
            renderSize = CGSize(width: bezelWidth, height: bezelHeight)
            scaledScreenRegion = screenRegion
        }

        // --- Build video composition with layer instruction ---
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)

        // Transform: apply preferred transform, optional extra rotation, then scale
        // to screen region and position.
        // The video composition renders in a coordinate system where (0,0) is top-left
        // and +Y goes down, matching CALayer conventions when isGeometryFlipped = true.
        let transformed = naturalSize.applying(preferredTransform)
        let baseWidth = abs(transformed.width)
        let baseHeight = abs(transformed.height)

        // After extra rotation, effective dimensions may swap
        let swapped = extraRotation == 90 || extraRotation == 270
        let videoWidth = swapped ? baseHeight : baseWidth
        let videoHeight = swapped ? baseWidth : baseHeight

        let scaleX = scaledScreenRegion.width / videoWidth
        let scaleY = scaledScreenRegion.height / videoHeight

        // screenRegion is in top-left-origin coordinates (from ScreenRegionDetector)
        let translateX = scaledScreenRegion.origin.x
        let translateY = scaledScreenRegion.origin.y

        // Combined transform: first apply preferredTransform (handles source rotation),
        // then extra user rotation, then scale to fit the screen region, then position.
        var t = preferredTransform

        // Apply extra rotation around the center of the post-preferredTransform frame
        if extraRotation != 0 {
            let radians = CGFloat(extraRotation) * .pi / 180.0
            // Move origin to center, rotate, move back. After preferredTransform the
            // frame occupies (0,0)-(baseWidth, baseHeight).
            t = t.concatenating(CGAffineTransform(translationX: -baseWidth / 2, y: -baseHeight / 2))
            t = t.concatenating(CGAffineTransform(rotationAngle: radians))
            t = t.concatenating(CGAffineTransform(translationX: videoWidth / 2, y: videoHeight / 2))
        }

        // Scale down to the screen region size
        t = t.concatenating(CGAffineTransform(scaleX: scaleX, y: scaleY))
        // Position in the bezel frame
        t = t.concatenating(CGAffineTransform(translationX: translateX, y: translateY))

        layerInstruction.setTransform(t, at: .zero)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [instruction]
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(nominalFrameRate > 0 ? nominalFrameRate : 30))

        // --- Build CALayer hierarchy for bezel overlay ---
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.isGeometryFlipped = true

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)

        // Mask the video layer to the screen hole shape (rounded corners)
        // so video pixels don't poke out behind the bezel's anti-aliased edges.
        // detectScreenMask returns a grayscale image (luminance-based), but CALayer
        // masks use the alpha channel, so we convert: draw white clipped by the
        // grayscale mask to produce an RGBA image with proper alpha.
        if let screenMask = ScreenRegionDetector.detectScreenMask(bezelFileName: bezelFileName),
           let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
           let ctx = CGContext(
               data: nil, width: bezelWidth, height: bezelHeight,
               bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
           ) {
            let fullRect = CGRect(x: 0, y: 0, width: bezelWidth, height: bezelHeight)
            ctx.clip(to: fullRect, mask: screenMask)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(fullRect)
            if let alphaMask = ctx.makeImage() {
                let maskLayer = CALayer()
                maskLayer.frame = CGRect(origin: .zero, size: renderSize)
                maskLayer.contents = alphaMask
                videoLayer.mask = maskLayer
            }
        }

        parentLayer.backgroundColor = backgroundColor
        parentLayer.addSublayer(videoLayer)

        let bezelLayer = CALayer()
        bezelLayer.frame = CGRect(origin: .zero, size: renderSize)
        bezelLayer.contents = bezelImage
        parentLayer.addSublayer(bezelLayer)

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        // --- Export ---
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw VideoExportError.exportSessionFailed
        }

        exportSession.videoComposition = videoComposition
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        // Poll progress concurrently while exporting
        let progressTask = Task {
            while !Task.isCancelled {
                let progress = Double(exportSession.progress)
                await progressHandler(progress)
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }

        await exportSession.export()

        progressTask.cancel()
        await progressHandler(1.0)

        if exportSession.status == .failed {
            throw exportSession.error ?? VideoExportError.exportFailed
        } else if exportSession.status == .cancelled {
            throw VideoExportError.exportCancelled
        }
    }

    enum VideoExportError: LocalizedError {
        case noVideoTrack
        case bezelNotFound
        case screenRegionNotFound
        case compositionFailed
        case exportSessionFailed
        case exportFailed
        case exportCancelled

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: "No video track found in file."
            case .bezelNotFound: "Could not load device bezel image."
            case .screenRegionNotFound: "Could not detect screen region for device."
            case .compositionFailed: "Failed to create video composition."
            case .exportSessionFailed: "Failed to create export session."
            case .exportFailed: "Video export failed."
            case .exportCancelled: "Video export was cancelled."
            }
        }
    }
}
