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

    /// Exports the video with the device bezel overlaid, preserving audio.
    static func export(
        asset: AVAsset,
        device: DeviceDefinition,
        color: DeviceColor,
        isLandscape: Bool,
        outputURL: URL,
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
            if let landscapeRegion = ScreenRegionDetector.detectScreenRegion(bezelFileName: landscapeBezelFileName) {
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

        // --- Build video composition with layer instruction ---
        let renderSize = CGSize(width: bezelWidth, height: bezelHeight)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)

        // Transform: apply preferred transform, then scale to screen region, then position
        // The video composition renders in a coordinate system where (0,0) is top-left
        // and +Y goes down, matching CALayer conventions when isGeometryFlipped = true.
        let transformed = naturalSize.applying(preferredTransform)
        let videoWidth = abs(transformed.width)
        let videoHeight = abs(transformed.height)

        let scaleX = screenRegion.width / videoWidth
        let scaleY = screenRegion.height / videoHeight

        // screenRegion is in top-left-origin coordinates (from ScreenRegionDetector)
        let translateX = screenRegion.origin.x
        let translateY = screenRegion.origin.y

        // Combined transform: first apply preferredTransform (handles rotation),
        // then scale to fit the screen region, then translate to position.
        //
        // preferredTransform may include a negative translation that moves the
        // rotated frame into the positive quadrant. We need to handle this along
        // with our scale and positioning.
        var t = preferredTransform
        // After preferredTransform, the video origin is at (0,0) in its natural
        // coordinate space. Scale it down to the screen region size.
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
        exportSession.outputFileType = .mov

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
