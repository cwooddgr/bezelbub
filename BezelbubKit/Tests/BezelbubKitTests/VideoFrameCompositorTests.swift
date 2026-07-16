import AVFoundation
import CoreGraphics
import ImageIO
import XCTest
@testable import BezelbubKit
@testable import BezelbubVideoKit

final class VideoFrameCompositorTests: XCTestCase {

    // End-to-end: synthesize a short solid-color video, frame it, and confirm
    // the export exists, matches the bezel's pixel size, keeps the source
    // duration, and reads back as a valid video. This also exercises the
    // export pipeline headless (swift test runs with no GUI session).
    func testVideoRoundTrip() async throws {
        let context = try await makeTestContext()

        let outputURL = context.tempDir.appendingPathComponent("framed.mp4")
        try await VideoFrameCompositor.export(
            asset: context.asset,
            device: context.device,
            color: context.device.defaultColor,
            isLandscape: false,
            background: .color(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)),
            outputURL: outputURL,
            progressHandler: { _ in }
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let framed = AVURLAsset(url: outputURL)
        let framedSize = try await VideoFrameCompositor.videoDimensions(asset: framed)
        // H.264 may pad to even dimensions, so allow a couple of pixels.
        XCTAssertEqual(framedSize.width, context.bezelSize.width, accuracy: 2)
        XCTAssertEqual(framedSize.height, context.bezelSize.height, accuracy: 2)

        let duration = try await framed.load(.duration).seconds
        XCTAssertEqual(duration, context.expectedDuration, accuracy: 0.1)
    }

    // The outputSize parameter drives the render size directly.
    func testVideoExportHonorsOutputSize() async throws {
        let context = try await makeTestContext()

        let target = CGSize(
            width: context.bezelSize.width / 4,
            height: context.bezelSize.height / 4
        )
        let outputURL = context.tempDir.appendingPathComponent("framed-small.mp4")
        try await VideoFrameCompositor.export(
            asset: context.asset,
            device: context.device,
            color: context.device.defaultColor,
            isLandscape: false,
            background: .color(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)),
            outputURL: outputURL,
            outputSize: target,
            progressHandler: { _ in }
        )

        let framed = AVURLAsset(url: outputURL)
        let framedSize = try await VideoFrameCompositor.videoDimensions(asset: framed)
        XCTAssertEqual(framedSize.width, Int(target.width), accuracy: 2)
        XCTAssertEqual(framedSize.height, Int(target.height), accuracy: 2)
    }

    // Transparent export: HEVC-with-alpha in a QuickTime container, with the
    // alpha channel actually surviving the encode — a corner pixel (outside
    // the device body) decodes as fully transparent while a screen-center
    // pixel (video content) decodes as fully opaque.
    func testTransparentVideoExportPreservesAlpha() async throws {
        let context = try await makeTestContext()

        let outputURL = context.tempDir.appendingPathComponent("framed.mov")
        try await VideoFrameCompositor.export(
            asset: context.asset,
            device: context.device,
            color: context.device.defaultColor,
            isLandscape: false,
            background: .transparent,
            outputURL: outputURL,
            progressHandler: { _ in }
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let framed = AVURLAsset(url: outputURL)

        // The track must be HEVC and declare an alpha channel.
        let videoTracks = try await framed.loadTracks(withMediaType: .video)
        let videoTrack = try XCTUnwrap(videoTracks.first)
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        let formatDescription = try XCTUnwrap(formatDescriptions.first)
        let codec = CMFormatDescriptionGetMediaSubType(formatDescription)
        XCTAssertTrue(
            codec == kCMVideoCodecType_HEVC || codec == kCMVideoCodecType_HEVCWithAlpha,
            "Expected HEVC codec, got \(codec)"
        )
        let containsAlpha = CMFormatDescriptionGetExtension(
            formatDescription,
            extensionKey: kCMFormatDescriptionExtension_ContainsAlphaChannel
        ) as? Bool
        XCTAssertEqual(containsAlpha, true, "Format description does not declare an alpha channel")

        // Decode the first frame and probe actual alpha values.
        let frame = try await firstFrameBGRA(url: outputURL)
        let cornerAlpha = frame.alpha(x: 4, y: 4)
        let centerAlpha = frame.alpha(x: frame.width / 2, y: frame.height / 2)
        XCTAssertLessThanOrEqual(cornerAlpha, 8, "Corner outside the bezel should be transparent")
        XCTAssertGreaterThanOrEqual(centerAlpha, 247, "Screen content should be opaque")

        // The bezel outline must be anti-aliased: a real edge has pixels with
        // 0 < alpha < 1, not a hard binary mask.
        XCTAssertGreaterThan(
            frame.partialAlphaCount(), 100,
            "Expected anti-aliased (partial-alpha) pixels along the bezel edge"
        )
    }

    // Transparency must survive output scaling: a 50% export still decodes
    // with transparent surroundings, opaque screen content, and anti-aliased
    // edges at the smaller size.
    func testTransparentVideoExportHonorsOutputSizeAndKeepsAlpha() async throws {
        let context = try await makeTestContext()

        let target = CGSize(
            width: context.bezelSize.width / 2,
            height: context.bezelSize.height / 2
        )
        let outputURL = context.tempDir.appendingPathComponent("framed-small.mov")
        try await VideoFrameCompositor.export(
            asset: context.asset,
            device: context.device,
            color: context.device.defaultColor,
            isLandscape: false,
            background: .transparent,
            outputURL: outputURL,
            outputSize: target,
            progressHandler: { _ in }
        )

        let framed = AVURLAsset(url: outputURL)
        let framedSize = try await VideoFrameCompositor.videoDimensions(asset: framed)
        XCTAssertEqual(framedSize.width, Int(target.width), accuracy: 2)
        XCTAssertEqual(framedSize.height, Int(target.height), accuracy: 2)

        let frame = try await firstFrameBGRA(url: outputURL)
        XCTAssertLessThanOrEqual(frame.alpha(x: 2, y: 2), 8)
        XCTAssertGreaterThanOrEqual(frame.alpha(x: frame.width / 2, y: frame.height / 2), 247)
        XCTAssertGreaterThan(frame.partialAlphaCount(), 100)
    }

    // The ProRes 4444 master that --webm renders for ffmpeg must itself carry
    // alpha; this isolates the first half of the WebM conversion chain.
    func testProResTransparentExportKeepsAlpha() async throws {
        let context = try await makeTestContext()

        let outputURL = context.tempDir.appendingPathComponent("master.mov")
        try await VideoFrameCompositor.export(
            asset: context.asset,
            device: context.device,
            color: context.device.defaultColor,
            isLandscape: false,
            background: .transparent,
            outputURL: outputURL,
            exportPreset: AVAssetExportPresetAppleProRes4444LPCM,
            progressHandler: { _ in }
        )

        let frame = try await firstFrameBGRA(url: outputURL)
        XCTAssertLessThanOrEqual(frame.alpha(x: 4, y: 4), 8)
        XCTAssertGreaterThanOrEqual(frame.alpha(x: frame.width / 2, y: frame.height / 2), 247)
        XCTAssertGreaterThan(frame.partialAlphaCount(), 100)
    }

    // MARK: - Fixtures

    private struct TestContext {
        let tempDir: URL
        let device: DeviceDefinition
        let asset: AVAsset
        let bezelSize: (width: Int, height: Int)
        let expectedDuration: Double
    }

    /// Writes a short solid-gray video at half the device's portrait screen
    /// size into a fresh temp directory and gathers everything the export
    /// assertions need.
    private func makeTestContext() async throws -> TestContext {
        let devices = DeviceCatalog.hydrated()
        let device = try XCTUnwrap(devices.first { $0.id == "iphone17pro" })
        let region = try XCTUnwrap(device.screenRegion)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BezelbubVideoTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // H.264 wants even dimensions; the exact size doesn't matter because
        // the compositor scales the video to fill the screen region.
        let width = (Int(region.width) / 2) & ~1
        let height = (Int(region.height) / 2) & ~1
        let frameCount = 12
        let fps: Int32 = 30
        let inputURL = tempDir.appendingPathComponent("input.mp4")
        try await TestVideoWriter.writeSolidVideo(
            to: inputURL, width: width, height: height, frameCount: frameCount, fps: fps
        )

        let bezelFileName = device.bezelFileName(color: device.defaultColor, landscape: false)
        let bezelURL = try XCTUnwrap(ScreenRegionDetector.bezelURL(fileName: bezelFileName))
        let bezelSource = try XCTUnwrap(CGImageSourceCreateWithURL(bezelURL as CFURL, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(bezelSource, 0, nil) as? [CFString: Any]
        )
        let bezelWidth = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
        let bezelHeight = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)

        return TestContext(
            tempDir: tempDir,
            device: device,
            asset: AVURLAsset(url: inputURL),
            bezelSize: (bezelWidth, bezelHeight),
            expectedDuration: Double(frameCount) / Double(fps)
        )
    }

    /// Decodes the first video frame into BGRA bytes so tests can assert on
    /// per-pixel alpha (AVAssetImageGenerator flattens alpha, AVAssetReader
    /// doesn't).
    private struct BGRAFrame {
        let bytes: [UInt8]
        let width: Int
        let height: Int
        let bytesPerRow: Int

        func alpha(x: Int, y: Int) -> UInt8 {
            bytes[y * bytesPerRow + x * 4 + 3]
        }

        /// Pixels that are neither fully transparent nor fully opaque —
        /// the signature of an anti-aliased edge. Tolerates codec noise by
        /// ignoring near-0/near-255 values.
        func partialAlphaCount() -> Int {
            var count = 0
            for y in 0..<height {
                for x in 0..<width {
                    let a = alpha(x: x, y: y)
                    if a > 16 && a < 240 { count += 1 }
                }
            }
            return count
        }
    }

    private func firstFrameBGRA(url: URL) async throws -> BGRAFrame {
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        reader.add(output)
        XCTAssertTrue(reader.startReading())

        let sampleBuffer = try XCTUnwrap(output.copyNextSampleBuffer())
        let pixelBuffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sampleBuffer))

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
        let bytes = [UInt8](UnsafeRawBufferPointer(start: base, count: bytesPerRow * height))

        reader.cancelReading()
        return BGRAFrame(bytes: bytes, width: width, height: height, bytesPerRow: bytesPerRow)
    }

}

private func XCTAssertEqual(_ a: Int, _ b: Int, accuracy: Int) {
    XCTAssertLessThanOrEqual(abs(a - b), accuracy, "\(a) is not within \(accuracy) of \(b)")
}
