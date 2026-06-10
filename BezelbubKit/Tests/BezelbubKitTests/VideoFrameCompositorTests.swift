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
            backgroundColor: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
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
            backgroundColor: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
            outputURL: outputURL,
            outputSize: target,
            progressHandler: { _ in }
        )

        let framed = AVURLAsset(url: outputURL)
        let framedSize = try await VideoFrameCompositor.videoDimensions(asset: framed)
        XCTAssertEqual(framedSize.width, Int(target.width), accuracy: 2)
        XCTAssertEqual(framedSize.height, Int(target.height), accuracy: 2)
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
        try await writeSolidVideo(
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

    private func writeSolidVideo(
        to url: URL, width: Int, height: Int, frameCount: Int, fps: Int32
    ) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            let pool = try XCTUnwrap(adaptor.pixelBufferPool)
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            let pixelBuffer = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
                memset(base, 0x80, CVPixelBufferGetDataSize(pixelBuffer))
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }

        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
    }
}

private func XCTAssertEqual(_ a: Int, _ b: Int, accuracy: Int) {
    XCTAssertLessThanOrEqual(abs(a - b), accuracy, "\(a) is not within \(accuracy) of \(b)")
}
