import ArgumentParser
import AVFoundation
import BezelbubKit
import BezelbubVideoKit
import CoreGraphics
import Foundation
import ImageIO

struct Frame: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "frame",
        abstract: "Frame a screenshot or screen recording in a device bezel.",
        discussion: """
        Image inputs (PNG/JPEG/HEIC) write a framed PNG. Video inputs \
        (.mov/.mp4/.m4v) write a framed MP4, preserving audio; --background \
        defaults to black there. Pass --background transparent to export \
        HEVC-with-alpha in a QuickTime .mov instead — transparent video plays \
        in Safari and Apple frameworks only; add --webm (requires ffmpeg on \
        PATH) to also write a VP9/WebM copy for Chrome and Firefox, or convert \
        manually with ffmpeg 8+ (older ffmpeg silently decodes HEVC alpha as \
        opaque): ffmpeg -i framed.mov -c:v libvpx-vp9 -pix_fmt yuva420p out.webm

        If --device is omitted, the device is auto-detected from the input's \
        pixel dimensions. Detection succeeds when exactly one device's screen \
        matches; if several share the resolution, the error lists the \
        candidates so you can re-run with --device <id>.

        Examples:
          bezelbub frame --input shot.png
          bezelbub frame --input shot.png --device iphone17pro --color "Cosmic Orange"
          bezelbub frame --input shot.png --background "#1D1D1F" --json
          bezelbub frame --input recording.mp4 --output-size 50%
          bezelbub frame --input recording.mp4 --background transparent --webm

        Discover valid device ids, colors, and screen sizes with `bezelbub \
        devices`, or ask which devices fit an input before framing: \
        `bezelbub devices --input shot.png`.
        """
    )

    @Option(name: .shortAndLong, help: "Path to the input screenshot (PNG/JPEG/HEIC) or video (MOV/MP4/M4V).")
    var input: String

    @Option(name: .shortAndLong, help: ArgumentHelp(
        "Device id. Omit to auto-detect from the input's pixel size.",
        discussion: "Run `bezelbub devices` to list valid ids."
    ))
    var device: String?

    @Option(name: .shortAndLong, help: "Color name or id. Defaults to the device's default color.")
    var color: String?

    @Option(help: "Orientation: portrait | landscape | auto (infer from the input).")
    var orientation: Orientation = .auto

    @Option(help: """
    Background fill as a hex color (e.g. #FFFFFF or #RRGGBBAA), or \
    "transparent". Default: transparent for images, black for video. \
    Transparent video exports HEVC-with-alpha as .mov (plays in Safari and \
    Apple apps only).
    """)
    var background: String?

    @Option(help: """
    Scale the output, preserving the bezel's aspect ratio: a width (1920), \
    an exact size (1920x988), or a percentage of native size (50%). \
    Default: the bezel's native size.
    """)
    var outputSize: String?

    @Option(name: .shortAndLong, help: """
    Output path. Default: <input>-framed.png (image) or <input>-framed.mp4 (video) \
    beside the input.
    """)
    var output: String?

    @Flag(help: """
    Also write a VP9/WebM copy of a transparent video export for Chrome/Firefox \
    playback. Requires --background transparent and ffmpeg on PATH.
    """)
    var webm = false

    @Flag(help: "Emit a machine-readable JSON result to stdout instead of a text summary.")
    var json = false

    /// Pure flag-combination checks live here so they fail with ArgumentParser's
    /// standard usage handling (exit 64) before any file is touched.
    func validate() throws {
        let isVideo = InputKind(path: input) == .video
        let transparent = isTransparentBackground

        if webm {
            guard isVideo else {
                throw ValidationError("--webm only applies to video inputs (.mov/.mp4/.m4v).")
            }
            guard transparent else {
                throw ValidationError(
                    "--webm requires --background transparent (WebM output exists to carry "
                        + "the alpha channel to non-Apple browsers)."
                )
            }
        }

        if isVideo, transparent, let output {
            guard URL(fileURLWithPath: output).pathExtension.lowercased() == "mov" else {
                throw ValidationError(
                    "Transparent video is HEVC-with-alpha, which requires a QuickTime "
                        + "container — use a .mov extension for --output (got '\(output)')."
                )
            }
        }
    }

    private var isTransparentBackground: Bool {
        background?.lowercased() == "transparent"
    }

    func run() async throws {
        let devices = DeviceCatalog.hydrated()
        switch InputKind(path: input) {
        case .image: try runImage(devices: devices)
        case .video: try await runVideo(devices: devices)
        }
    }

    // MARK: - Image path

    private func runImage(devices: [DeviceDefinition]) throws {
        // Future stdin/base64 support slots in here: if `input == "-"`, read raw
        // bytes from FileHandle.standardInput and use CGImageSourceCreateWithData.
        let inputURL = URL(fileURLWithPath: input)
        let screenshot = try loadInputImage(atPath: input)

        let (device, autoDetected) = try resolveDevice(
            in: devices, inputWidth: screenshot.width, inputHeight: screenshot.height, noun: "screenshot"
        )
        let resolvedColor = try resolveColor(for: device)

        let isLandscape: Bool
        switch orientation {
        case .portrait: isLandscape = false
        case .landscape: isLandscape = true
        case .auto: isLandscape = device.landscapeOnly || screenshot.width > screenshot.height
        }

        // --- Resolve background (images support transparency, so nil = clear;
        // the explicit "transparent" keyword is a synonym for the default) ---
        let backgroundColor: CGColor?
        if let background, !isTransparentBackground {
            guard let parsed = CGColor.fromHex(background) else {
                throw fail(
                    "Invalid --background '\(background)'. Use hex like #RRGGBB, "
                        + "#RRGGBBAA, or \"transparent\".",
                    code: .usage
                )
            }
            backgroundColor = parsed
        } else {
            backgroundColor = nil
        }

        // --- Composite ---
        guard var framed = FrameCompositor.composite(
            screenshot: screenshot,
            device: device,
            color: resolvedColor,
            isLandscape: isLandscape,
            backgroundColor: backgroundColor
        ) else {
            throw fail(
                "Compositing failed — no bezel/region for \(device.id) (\(resolvedColor.id), "
                    + "\(isLandscape ? "landscape" : "portrait")).",
                code: .compositeFailed
            )
        }

        // --- Scale to --output-size ---
        if let outputSize {
            let target = try resolveOutputSize(
                outputSize, nativeWidth: framed.width, nativeHeight: framed.height, isVideo: false
            )
            if target.width != framed.width || target.height != framed.height {
                guard let scaled = scaleImage(framed, to: target) else {
                    throw fail(
                        "Could not scale the framed image to \(target.width)×\(target.height).",
                        code: .compositeFailed
                    )
                }
                framed = scaled
            }
        }

        // --- Resolve output path ---
        let outputURL: URL
        if let output {
            outputURL = URL(fileURLWithPath: output)
        } else {
            let base = inputURL.deletingPathExtension().lastPathComponent
            outputURL = inputURL.deletingLastPathComponent()
                .appendingPathComponent("\(base)-framed.png")
        }

        // --- Write ---
        guard FrameCompositor.savePNG(image: framed, to: outputURL) else {
            throw fail("Could not write output to \(outputURL.path).", code: .writeFailed)
        }

        try report(
            kind: "image",
            device: device,
            autoDetected: autoDetected,
            inputWidth: screenshot.width,
            inputHeight: screenshot.height,
            color: resolvedColor,
            isLandscape: isLandscape,
            outputURL: outputURL,
            outputWidth: framed.width,
            outputHeight: framed.height
        )
    }

    // MARK: - Video path

    private func runVideo(devices: [DeviceDefinition]) async throws {
        // --- Locate ffmpeg before anything else so --webm fails fast rather
        // than after a long export ---
        var ffmpegURL: URL?
        if webm {
            guard let found = findExecutable("ffmpeg") else {
                throw fail(
                    "--webm needs ffmpeg, which isn't on your PATH. "
                        + "Install it (brew install ffmpeg) and re-run.",
                    code: .ffmpegFailed
                )
            }
            ffmpegURL = found
        }

        let inputURL = URL(fileURLWithPath: input)
        let (asset, videoWidth, videoHeight) = try await loadInputVideo(atPath: input)

        let (device, autoDetected) = try resolveDevice(
            in: devices, inputWidth: videoWidth, inputHeight: videoHeight, noun: "video"
        )
        let resolvedColor = try resolveColor(for: device)

        let isLandscape: Bool
        switch orientation {
        case .portrait: isLandscape = false
        case .landscape: isLandscape = true
        case .auto: isLandscape = device.landscapeOnly || videoWidth > videoHeight
        }

        // --- Resolve background. "transparent" exports HEVC-with-alpha .mov;
        // a hex color exports opaque MP4 (no alpha there, so any alpha
        // component the hex carries is flattened) ---
        let videoBackground: VideoBackground
        let transparent = isTransparentBackground
        if transparent {
            videoBackground = .transparent
        } else if let background {
            guard let parsed = CGColor.fromHex(background) else {
                throw fail(
                    "Invalid --background '\(background)'. Use hex like #RRGGBB, "
                        + "#RRGGBBAA, or \"transparent\".",
                    code: .usage
                )
            }
            videoBackground = .color(parsed.copy(alpha: 1) ?? parsed)
        } else {
            videoBackground = .color(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        }

        // --- Resolve --output-size against the bezel's native pixel size ---
        let native = try bezelPixelSize(device: device, color: resolvedColor, isLandscape: isLandscape)
        var exportSize: CGSize?
        if let outputSize {
            let target = try resolveOutputSize(
                outputSize, nativeWidth: native.width, nativeHeight: native.height, isVideo: true
            )
            if target.width != native.width || target.height != native.height {
                exportSize = CGSize(width: target.width, height: target.height)
            }
        }

        // --- Resolve output path (AVAssetExportSession refuses to overwrite,
        // so clear the way first to match the image path's overwrite behavior) ---
        let outputURL: URL
        if let output {
            outputURL = URL(fileURLWithPath: output)
        } else {
            let base = inputURL.deletingPathExtension().lastPathComponent
            outputURL = inputURL.deletingLastPathComponent()
                .appendingPathComponent("\(base)-framed.\(transparent ? "mov" : "mp4")")
        }
        if FileManager.default.fileExists(atPath: outputURL.path) {
            do {
                try FileManager.default.removeItem(at: outputURL)
            } catch {
                throw fail(
                    "Could not overwrite \(outputURL.path): \(error.localizedDescription)",
                    code: .writeFailed
                )
            }
        }

        // --- Export, narrating progress on stderr when a human is watching ---
        let showProgress = !json && isatty(STDERR_FILENO) != 0
        do {
            try await VideoFrameCompositor.export(
                asset: asset,
                device: device,
                color: resolvedColor,
                isLandscape: isLandscape,
                background: videoBackground,
                outputURL: outputURL,
                outputSize: exportSize,
                progressHandler: { progress in
                    guard showProgress else { return }
                    let percent = Int((progress * 100).rounded())
                    FileHandle.standardError.write(Data("\rFraming video… \(percent)%".utf8))
                }
            )
        } catch {
            if showProgress {
                FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))
            }
            throw fail(
                "Video export failed — \(error.localizedDescription)",
                code: .compositeFailed
            )
        }
        if showProgress {
            FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))
        }

        // --- Optional VP9/WebM copy for non-Apple browsers ---
        // ffmpeg cannot decode HEVC's alpha layer (it comes back fully opaque),
        // so the conversion renders a ProRes 4444 master — whose alpha every
        // decoder understands — and feeds that to ffmpeg instead of the final
        // HEVC .mov.
        var webmURL: URL?
        if let ffmpegURL {
            let target = outputURL.deletingPathExtension().appendingPathExtension("webm")
            let master = FileManager.default.temporaryDirectory
                .appendingPathComponent("bezelbub-webm-master-\(UUID().uuidString).mov")
            defer { try? FileManager.default.removeItem(at: master) }
            do {
                try await VideoFrameCompositor.export(
                    asset: asset,
                    device: device,
                    color: resolvedColor,
                    isLandscape: isLandscape,
                    background: .transparent,
                    outputURL: master,
                    outputSize: exportSize,
                    exportPreset: AVAssetExportPresetAppleProRes4444LPCM,
                    progressHandler: { progress in
                        guard showProgress else { return }
                        let percent = Int((progress * 100).rounded())
                        FileHandle.standardError.write(Data("\rRendering WebM master… \(percent)%".utf8))
                    }
                )
            } catch {
                if showProgress {
                    FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))
                }
                throw fail(
                    "WebM master export failed — \(error.localizedDescription)",
                    code: .compositeFailed
                )
            }
            if showProgress {
                FileHandle.standardError.write(Data("\r\u{1B}[KConverting to WebM (VP9)…\n".utf8))
            }
            try runFFmpeg(at: ffmpegURL, input: master, output: target)
            webmURL = target
        }

        try report(
            kind: "video",
            device: device,
            autoDetected: autoDetected,
            inputWidth: videoWidth,
            inputHeight: videoHeight,
            color: resolvedColor,
            isLandscape: isLandscape,
            outputURL: outputURL,
            outputWidth: exportSize.map { Int($0.width) } ?? native.width,
            outputHeight: exportSize.map { Int($0.height) } ?? native.height,
            transparent: transparent,
            webmURL: webmURL
        )

        // A transparent export without --webm only plays in Safari/Apple apps;
        // nudge interactive users toward the cross-browser pair.
        if transparent && !webm && showProgress {
            let tip = "Tip: transparent video plays in Safari and Apple apps only. "
                + "Add --webm (needs ffmpeg) for a Chrome/Firefox-compatible copy.\n"
            FileHandle.standardError.write(Data(tip.utf8))
        }
    }

    /// Converts a framed ProRes 4444 master into VP9/WebM, preserving the
    /// alpha channel (yuva420p). ffmpeg noise is captured and only surfaced
    /// on failure.
    private func runFFmpeg(at ffmpegURL: URL, input: URL, output: URL) throws {
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = [
            "-y",
            "-i", input.path,
            "-c:v", "libvpx-vp9",
            "-pix_fmt", "yuva420p",
            output.path,
        ]
        let stderrPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw fail(
                "Could not launch ffmpeg at \(ffmpegURL.path): \(error.localizedDescription)",
                code: .ffmpegFailed
            )
        }
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let noise = String(decoding: stderrData, as: UTF8.self)
            let tail = noise.split(separator: "\n").suffix(6).joined(separator: "\n")
            throw fail(
                "ffmpeg failed converting to WebM (exit \(process.terminationStatus)):\n\(tail)",
                code: .ffmpegFailed
            )
        }
    }

    /// Reads the bezel PNG's pixel size from its metadata (no decode) so
    /// `--output-size` specs can resolve before the export pipeline runs.
    private func bezelPixelSize(
        device: DeviceDefinition,
        color: DeviceColor,
        isLandscape: Bool
    ) throws -> (width: Int, height: Int) {
        let fileName = device.bezelFileName(color: color, landscape: isLandscape)
        guard let url = ScreenRegionDetector.bezelURL(fileName: fileName),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            throw fail(
                "Compositing failed — no bezel for \(device.id) (\(color.id), "
                    + "\(isLandscape ? "landscape" : "portrait")).",
                code: .compositeFailed
            )
        }
        return (width, height)
    }

    // MARK: - Shared resolution + reporting

    /// Resolves `--color` against the device's catalog entry (case-insensitive
    /// id or display name), defaulting to the device's default color.
    private func resolveColor(for device: DeviceDefinition) throws -> DeviceColor {
        guard let color else { return device.defaultColor }
        let needle = color.lowercased()
        guard let match = device.colors.first(where: {
            $0.id.lowercased() == needle || $0.displayName.lowercased() == needle
        }) else {
            var message = "Unknown color '\(color)' for \(device.id)."
            let suggestions = DeviceCatalog.suggestColors(matching: color, in: device)
            if !suggestions.isEmpty {
                message += " Did you mean: \(suggestions.map(\.id).joined(separator: ", "))?"
            }
            message += " Valid colors: \(device.colors.map(\.id).joined(separator: ", "))"
                + " (default: \(device.defaultColor.id)). Matching is case-insensitive."
            throw fail(message, code: .unknownColor)
        }
        return match
    }

    /// Resolves `--device` to a catalog entry, or — when the flag is omitted —
    /// auto-detects the device from the input's pixel size. Every failure
    /// path lists concrete candidate ids so a non-interactive caller can
    /// correct itself on the next invocation. `noun` names the input in
    /// messages ("screenshot" or "video").
    private func resolveDevice(
        in devices: [DeviceDefinition],
        inputWidth: Int,
        inputHeight: Int,
        noun: String
    ) throws -> (device: DeviceDefinition, autoDetected: Bool) {
        let matches = DeviceMatcher.match(
            screenshotWidth: inputWidth,
            screenshotHeight: inputHeight,
            devices: devices
        )

        if let id = self.device {
            if let exact = devices.first(where: { $0.id == id }) {
                return (exact, false)
            }
            var message = "Unknown device '\(id)'."
            let suggestions = DeviceCatalog.suggestDevices(matching: id, in: devices)
            if !suggestions.isEmpty {
                message += "\nDid you mean:\n\(deviceList(suggestions))"
            }
            if !matches.isEmpty {
                message += "\nDevices matching the \(noun)'s "
                    + "\(inputWidth)×\(inputHeight) px:\n\(deviceList(matches.map(\.device)))"
            }
            message += "\nRun `bezelbub devices` to list all valid ids."
            throw fail(message, code: .unknownDevice)
        }

        switch matches.count {
        case 1:
            return (matches[0].device, true)
        case 0:
            var message = "No --device given, and no device's screen matches the \(noun)'s "
                + "\(inputWidth)×\(inputHeight) px."
            let nearest = DeviceMatcher.nearest(
                screenshotWidth: inputWidth,
                screenshotHeight: inputHeight,
                devices: devices
            )
            if !nearest.isEmpty {
                message += "\nNearest by aspect ratio:\n\(deviceList(nearest.map(\.device)))"
            }
            message += "\nResize the \(noun) to a device's native screen size, or pass "
                + "--device <id> to force it (the \(noun) is composited at native pixel "
                + "size, so a mismatch will look wrong). Run `bezelbub devices` for the full list."
            throw fail(message, code: .unknownDevice)
        default:
            let message = "The \(noun)'s \(inputWidth)×\(inputHeight) px matches "
                + "\(matches.count) devices, so --device is required. Candidates:\n"
                + deviceList(matches.map(\.device))
                + "\nRe-run with --device <id>."
            throw fail(message, code: .unknownDevice)
        }
    }

    private func report(
        kind: String,
        device: DeviceDefinition,
        autoDetected: Bool,
        inputWidth: Int,
        inputHeight: Int,
        color: DeviceColor,
        isLandscape: Bool,
        outputURL: URL,
        outputWidth: Int,
        outputHeight: Int,
        transparent: Bool? = nil,
        webmURL: URL? = nil
    ) throws {
        let orientationName = isLandscape ? "landscape" : "portrait"
        if json {
            let result = FrameResult(
                kind: kind,
                device: device.id,
                color: color.id,
                orientation: orientationName,
                output: outputURL.path,
                width: outputWidth,
                height: outputHeight,
                transparent: transparent,
                webm: webmURL?.path
            )
            print(try JSON.string(result))
        } else {
            if autoDetected {
                print(
                    "Auto-detected \(device.id) (\(device.displayName)) from the "
                        + "\(inputWidth)×\(inputHeight) px input."
                )
            }
            print(
                "Framed \(device.id) (\(color.id), \(orientationName)) → "
                    + "\(outputURL.path) [\(outputWidth)×\(outputHeight)]"
            )
            if let webmURL {
                print("WebM (VP9) copy → \(webmURL.path)")
            }
            if self.color == nil && device.colors.count > 1 {
                let others = device.colors
                    .filter { $0.id != color.id }
                    .map { "\"\($0.id)\"" }
                    .joined(separator: ", ")
                print(
                    "Used \(device.id)'s default color; it also comes in \(others). "
                        + "Re-run with --color <name> to use one."
                )
            }
        }
    }
}
