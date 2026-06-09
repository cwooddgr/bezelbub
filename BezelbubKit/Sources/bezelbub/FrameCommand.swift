import ArgumentParser
import BezelbubKit
import CoreGraphics
import Foundation
import ImageIO

struct Frame: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "frame",
        abstract: "Frame a screenshot in a device bezel and write a PNG.",
        discussion: """
        If --device is omitted, the device is auto-detected from the \
        screenshot's pixel dimensions. Detection succeeds when exactly one \
        device's screen matches; if several share the resolution, the error \
        lists the candidates so you can re-run with --device <id>.

        Examples:
          bezelbub frame --input shot.png
          bezelbub frame --input shot.png --device iphone17pro --color "Cosmic Orange"
          bezelbub frame --input shot.png --background "#1D1D1F" --json

        Discover valid device ids, colors, and screen sizes with `bezelbub \
        devices`, or ask which devices fit a screenshot before framing: \
        `bezelbub devices --input shot.png`.
        """
    )

    @Option(name: .shortAndLong, help: "Path to the input screenshot (PNG/JPEG/HEIC).")
    var input: String

    @Option(name: .shortAndLong, help: ArgumentHelp(
        "Device id. Omit to auto-detect from the screenshot's pixel size.",
        discussion: "Run `bezelbub devices` to list valid ids."
    ))
    var device: String?

    @Option(name: .shortAndLong, help: "Color name or id. Defaults to the device's default color.")
    var color: String?

    @Option(help: "Orientation: portrait | landscape | auto (infer from the screenshot).")
    var orientation: Orientation = .auto

    @Option(help: "Background fill as a hex color (e.g. #FFFFFF or #RRGGBBAA). Default: transparent.")
    var background: String?

    @Option(name: .shortAndLong, help: "Output PNG path. Default: <input>-framed.png beside the input.")
    var output: String?

    @Flag(help: "Emit a machine-readable JSON result to stdout instead of a text summary.")
    var json = false

    func run() throws {
        let devices = DeviceCatalog.hydrated()

        // --- Load input image (also needed for device auto-detection) ---
        // Future stdin/base64 support slots in here: if `input == "-"`, read raw
        // bytes from FileHandle.standardInput and use CGImageSourceCreateWithData.
        let inputURL = URL(fileURLWithPath: input)
        let screenshot = try loadInputImage(atPath: input)

        // --- Resolve device (explicit id, or auto-detect from pixel size) ---
        let (device, autoDetected) = try resolveDevice(in: devices, screenshot: screenshot)

        // --- Resolve color (case-insensitive against id or display name) ---
        let resolvedColor: DeviceColor
        if let color {
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
            resolvedColor = match
        } else {
            resolvedColor = device.defaultColor
        }

        // --- Resolve orientation ---
        let isLandscape: Bool
        switch orientation {
        case .portrait: isLandscape = false
        case .landscape: isLandscape = true
        case .auto: isLandscape = device.landscapeOnly || screenshot.width > screenshot.height
        }

        // --- Resolve background ---
        let backgroundColor: CGColor?
        if let background {
            guard let parsed = CGColor.fromHex(background) else {
                throw fail(
                    "Invalid --background '\(background)'. Use hex like #RRGGBB or #RRGGBBAA.",
                    code: .usage
                )
            }
            backgroundColor = parsed
        } else {
            backgroundColor = nil
        }

        // --- Composite ---
        guard let framed = FrameCompositor.composite(
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

        // --- Report ---
        let orientationName = isLandscape ? "landscape" : "portrait"
        if json {
            let result = FrameResult(
                device: device.id,
                color: resolvedColor.id,
                orientation: orientationName,
                output: outputURL.path,
                width: framed.width,
                height: framed.height
            )
            print(try JSON.string(result))
        } else {
            if autoDetected {
                print(
                    "Auto-detected \(device.id) (\(device.displayName)) from the "
                        + "\(screenshot.width)×\(screenshot.height) px input."
                )
            }
            print(
                "Framed \(device.id) (\(resolvedColor.id), \(orientationName)) → "
                    + "\(outputURL.path) [\(framed.width)×\(framed.height)]"
            )
            if color == nil && device.colors.count > 1 {
                let others = device.colors
                    .filter { $0.id != resolvedColor.id }
                    .map { "\"\($0.id)\"" }
                    .joined(separator: ", ")
                print(
                    "Used \(device.id)'s default color; it also comes in \(others). "
                        + "Re-run with --color <name> to use one."
                )
            }
        }
    }

    /// Resolves `--device` to a catalog entry, or — when the flag is omitted —
    /// auto-detects the device from the screenshot's pixel size. Every failure
    /// path lists concrete candidate ids so a non-interactive caller can
    /// correct itself on the next invocation.
    private func resolveDevice(
        in devices: [DeviceDefinition],
        screenshot: CGImage
    ) throws -> (device: DeviceDefinition, autoDetected: Bool) {
        let matches = DeviceMatcher.match(
            screenshotWidth: screenshot.width,
            screenshotHeight: screenshot.height,
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
                message += "\nDevices matching the screenshot's "
                    + "\(screenshot.width)×\(screenshot.height) px:\n\(deviceList(matches.map(\.device)))"
            }
            message += "\nRun `bezelbub devices` to list all valid ids."
            throw fail(message, code: .unknownDevice)
        }

        switch matches.count {
        case 1:
            return (matches[0].device, true)
        case 0:
            var message = "No --device given, and no device's screen matches the screenshot's "
                + "\(screenshot.width)×\(screenshot.height) px."
            let nearest = DeviceMatcher.nearest(
                screenshotWidth: screenshot.width,
                screenshotHeight: screenshot.height,
                devices: devices
            )
            if !nearest.isEmpty {
                message += "\nNearest by aspect ratio:\n\(deviceList(nearest.map(\.device)))"
            }
            message += "\nResize the screenshot to a device's native screen size, or pass "
                + "--device <id> to force it (the screenshot is composited at native pixel "
                + "size, so a mismatch will look wrong). Run `bezelbub devices` for the full list."
            throw fail(message, code: .unknownDevice)
        default:
            let message = "The screenshot's \(screenshot.width)×\(screenshot.height) px matches "
                + "\(matches.count) devices, so --device is required. Candidates:\n"
                + deviceList(matches.map(\.device))
                + "\nRe-run with --device <id>."
            throw fail(message, code: .unknownDevice)
        }
    }
}
