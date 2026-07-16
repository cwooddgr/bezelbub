import AVFoundation
import Foundation
import XCTest

/// Exercises the `bezelbub` executable's fast error paths for transparent
/// video / --webm flag handling. These run the real binary (swift test builds
/// it alongside the libraries) but never reach the export pipeline, so they
/// stay fast.
final class CLIFrameTests: XCTestCase {

    // --webm without --background transparent is a flag-combination error,
    // caught by ArgumentParser validation (EX_USAGE) before any file I/O.
    func testWebmRequiresTransparentBackground() throws {
        let result = try runCLI(["frame", "--input", "clip.mov", "--webm"])
        XCTAssertEqual(result.status, 64)
        XCTAssertTrue(result.stderr.contains("--background transparent"), result.stderr)
    }

    func testWebmRejectsImageInput() throws {
        let result = try runCLI([
            "frame", "--input", "shot.png", "--background", "transparent", "--webm",
        ])
        XCTAssertEqual(result.status, 64)
        XCTAssertTrue(result.stderr.contains("video inputs"), result.stderr)
    }

    // Transparent video is HEVC-with-alpha, which only fits a QuickTime container.
    func testTransparentVideoRejectsNonMovOutput() throws {
        let result = try runCLI([
            "frame", "--input", "clip.mov", "--background", "transparent",
            "--output", "framed.mp4",
        ])
        XCTAssertEqual(result.status, 64)
        XCTAssertTrue(result.stderr.contains(".mov"), result.stderr)
    }

    // ffmpeg discovery happens before the export so --webm fails fast; with a
    // PATH that can't contain it, the run exits 7 with an install hint.
    func testWebmWithoutFFmpegExitsSeven() throws {
        let result = try runCLI(
            ["frame", "--input", "clip.mov", "--background", "transparent", "--webm"],
            environment: ["PATH": ""]
        )
        XCTAssertEqual(result.status, 7)
        XCTAssertTrue(result.stderr.contains("ffmpeg"), result.stderr)
        XCTAssertTrue(result.stderr.contains("brew install ffmpeg"), result.stderr)
    }

    // End-to-end regression test for the WebM alpha chain: ffmpeg cannot
    // decode HEVC's alpha layer, so --webm must convert from a ProRes master —
    // if it ever feeds ffmpeg the HEVC .mov instead, the WebM comes out fully
    // opaque and this test fails. Skipped when ffmpeg isn't installed.
    func testWebmOutputCarriesAlpha() async throws {
        guard findFFmpeg() != nil else {
            throw XCTSkip("ffmpeg not on PATH; skipping WebM integration test")
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BezelbubCLITests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let inputURL = tempDir.appendingPathComponent("clip.mov")
        try await TestVideoWriter.writeSolidVideo(to: inputURL, width: 602, height: 1310, frameCount: 6, fps: 30)

        // --output-size also exercises the scaled transparent path end to end
        // (and keeps the VP9 encode fast).
        let outputURL = tempDir.appendingPathComponent("framed.mov")
        let result = try runCLI([
            "frame", "--input", inputURL.path, "--device", "iphone17pro",
            "--background", "transparent", "--webm",
            "--output-size", "25%", "--output", outputURL.path, "--json",
        ])
        XCTAssertEqual(result.status, 0, result.stderr)

        let webmURL = tempDir.appendingPathComponent("framed.webm")
        XCTAssertTrue(FileManager.default.fileExists(atPath: webmURL.path))
        XCTAssertTrue(result.stdout.contains("\"transparent\" : true"), result.stdout)
        XCTAssertTrue(result.stdout.contains("framed.webm"), result.stdout)

        // Decode the WebM's first frame via ffmpeg and histogram the alpha.
        let stats = try webmAlphaStats(url: webmURL)
        XCTAssertGreaterThan(stats.transparent, 0, "WebM lost full transparency")
        XCTAssertGreaterThan(stats.partial, 0, "WebM lost anti-aliased (partial-alpha) edges")
        XCTAssertGreaterThan(stats.opaque, 0, "WebM has no opaque content")
    }

    // MARK: - Harness

    private struct CLIResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private func runCLI(_ arguments: [String], environment: [String: String]? = nil) throws -> CLIResult {
        let process = Process()
        process.executableURL = productsDirectory.appendingPathComponent("bezelbub")
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return CLIResult(
            status: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self)
        )
    }

    /// The build products directory containing the compiled `bezelbub` binary,
    /// located from the test bundle's own path.
    private var productsDirectory: URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("couldn't find the products directory")
    }

    /// PATH lookup mirroring the CLI's own ffmpeg discovery.
    private func findFFmpeg() -> URL? {
        guard let path = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        for directory in path.split(separator: ":") where !directory.isEmpty {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("ffmpeg")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Decodes the WebM's first frame to raw RGBA via ffmpeg and counts fully
    /// transparent, partial, and fully opaque alpha values.
    private func webmAlphaStats(url: URL) throws -> (transparent: Int, partial: Int, opaque: Int) {
        let ffmpeg = try XCTUnwrap(findFFmpeg())
        let process = Process()
        process.executableURL = ffmpeg
        // -c:v libvpx-vp9 forces the libvpx DECODER — ffmpeg's native VP9
        // decoder silently ignores the alpha side-channel and reports every
        // pixel as opaque.
        process.arguments = [
            "-v", "error",
            "-c:v", "libvpx-vp9",
            "-i", url.path,
            "-frames:v", "1",
            "-pix_fmt", "rgba",
            "-f", "rawvideo",
            "-",
        ]
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "ffmpeg failed to decode the WebM")

        var transparent = 0, partial = 0, opaque = 0
        var index = 3
        while index < data.count {
            switch data[index] {
            case 0: transparent += 1
            case 255: opaque += 1
            default: partial += 1
            }
            index += 4
        }
        return (transparent, partial, opaque)
    }
}
