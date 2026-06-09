import ArgumentParser
import BezelbubKit
import CoreGraphics
import Foundation
import ImageIO

struct Frame: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "frame",
        abstract: "Frame a screenshot in a device bezel and write a PNG."
    )

    @Option(name: .shortAndLong, help: "Path to the input screenshot (PNG/JPEG/HEIC).")
    var input: String

    @Option(name: .shortAndLong, help: "Device id. Run `bezelbub devices` to list them.")
    var device: String

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
        // --- Resolve device ---
        let devices = DeviceCatalog.hydrated()
        guard let device = devices.first(where: { $0.id == self.device }) else {
            throw fail(
                "Unknown device '\(self.device)'. Run `bezelbub devices` to list valid ids.",
                code: .unknownDevice
            )
        }

        // --- Resolve color (case-insensitive against id or display name) ---
        let resolvedColor: DeviceColor
        if let color {
            let needle = color.lowercased()
            guard let match = device.colors.first(where: {
                $0.id.lowercased() == needle || $0.displayName.lowercased() == needle
            }) else {
                let available = device.colors.map(\.id).joined(separator: ", ")
                throw fail(
                    "Unknown color '\(color)' for \(device.id). Available: \(available).",
                    code: .unknownColor
                )
            }
            resolvedColor = match
        } else {
            resolvedColor = device.defaultColor
        }

        // --- Load input image ---
        // Future stdin/base64 support slots in here: if `input == "-"`, read raw
        // bytes from FileHandle.standardInput and use CGImageSourceCreateWithData.
        let inputURL = URL(fileURLWithPath: input)
        guard let screenshot = Self.loadImage(at: inputURL) else {
            throw fail("Could not read input image at \(input).", code: .unreadableInput)
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
            print(
                "Framed \(device.id) (\(resolvedColor.id), \(orientationName)) → "
                    + "\(outputURL.path) [\(framed.width)×\(framed.height)]"
            )
        }
    }

    /// Loads an image and realizes it into sRGB so palette/indexed PNGs composite
    /// correctly (CGContext can't draw indexed color spaces), matching the app.
    static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: image.width, height: image.height,
                  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            return image
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage() ?? image
    }
}
