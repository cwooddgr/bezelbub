import ArgumentParser
import BezelbubKit
import CoreGraphics
import Foundation
import ImageIO

// MARK: - Orientation

enum Orientation: String, ExpressibleByArgument, CaseIterable {
    case portrait
    case landscape
    /// Infer from the screenshot's aspect (landscape if wider than tall).
    case auto
}

// MARK: - Exit codes

/// Stable, distinct exit codes so scripts and agents can branch on failure type
/// rather than parsing stderr text. ArgumentParser's own parse failures exit 64
/// (EX_USAGE); 1 covers other usage errors (e.g. a malformed --background).
enum ExitStatus: Int32 {
    case usage = 1
    /// Unknown, ambiguous, or undetectable device — stderr lists candidates.
    case unknownDevice = 2
    case unknownColor = 3
    case unreadableInput = 4
    case compositeFailed = 5
    case writeFailed = 6
}

/// Writes a human-readable message to stderr and returns an `ExitCode` carrying
/// the chosen status. Throw the result: `throw fail("…", code: .unknownDevice)`.
/// (`ExitCode` itself prints nothing, so the message isn't duplicated.)
func fail(_ message: String, code: ExitStatus) -> ExitCode {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    return ExitCode(code.rawValue)
}

// MARK: - Image loading

/// Loads an image and realizes it into sRGB so palette/indexed PNGs composite
/// correctly (CGContext can't draw indexed color spaces), matching the app.
func loadImage(at url: URL) -> CGImage? {
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

// MARK: - Suggestion formatting

/// One device per line for error messages and match listings, e.g.
/// `  iphone17pro — iPhone 17 Pro, screen 1206×2622 px`.
func deviceList(_ devices: [DeviceDefinition]) -> String {
    devices.map { device in
        var line = "  \(device.id) — \(device.displayName)"
        if let region = device.screenRegion {
            line += ", screen \(Int(region.width))×\(Int(region.height)) px"
        }
        return line
    }.joined(separator: "\n")
}

/// Parses `1206x2622` (also accepts `×` or uppercase `X`) into a pixel size.
func parseDimensions(_ string: String) -> (width: Int, height: Int)? {
    let parts = string.lowercased().split(whereSeparator: { $0 == "x" || $0 == "×" })
    guard parts.count == 2,
          let width = Int(parts[0]), let height = Int(parts[1]),
          width > 0, height > 0
    else {
        return nil
    }
    return (width, height)
}

// MARK: - Hex color parsing

extension CGColor {
    /// Parses `#RRGGBB`, `RRGGBB`, `#RRGGBBAA`, or `RRGGBBAA` into an sRGB color.
    static func fromHex(_ hex: String) -> CGColor? {
        var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        s = s.uppercased()
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else {
            return nil
        }
        let r, g, b, a: CGFloat
        if s.count == 6 {
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >> 8) & 0xFF) / 255
            b = CGFloat(value & 0xFF) / 255
            a = 1
        } else {
            r = CGFloat((value >> 24) & 0xFF) / 255
            g = CGFloat((value >> 16) & 0xFF) / 255
            b = CGFloat((value >> 8) & 0xFF) / 255
            a = CGFloat(value & 0xFF) / 255
        }
        return CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

// MARK: - JSON

enum JSON {
    static func string<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

/// `bezelbub frame --json` result envelope.
struct FrameResult: Encodable {
    let device: String
    let color: String
    let orientation: String
    let output: String
    let width: Int
    let height: Int
}

/// `bezelbub devices --input/--dimensions --json` result envelope: the queried
/// size, the devices whose screens match it, and (only when `matches` is
/// empty) the nearest devices by aspect ratio.
struct DeviceMatchResult: Encodable {
    let width: Int
    let height: Int
    let matches: [DeviceInfo]
    let nearest: [DeviceInfo]
}

/// One entry of `bezelbub devices --json`.
struct DeviceInfo: Encodable {
    let id: String
    let displayName: String
    let defaultColor: String
    let colors: [String]
    let landscapeOnly: Bool
    let hasPortraitBezel: Bool
    let screenWidth: Int?
    let screenHeight: Int?

    init(_ device: DeviceDefinition) {
        id = device.id
        displayName = device.displayName
        defaultColor = device.defaultColor.id
        colors = device.colors.map(\.id)
        landscapeOnly = device.landscapeOnly
        hasPortraitBezel = device.hasPortraitBezel
        screenWidth = device.screenRegion.map { Int($0.width) }
        screenHeight = device.screenRegion.map { Int($0.height) }
    }
}
