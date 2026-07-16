import ArgumentParser
import AVFoundation
import BezelbubKit
import BezelbubVideoKit
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
    /// `--webm` conversion: ffmpeg missing from PATH, or it exited nonzero.
    case ffmpegFailed = 7
}

/// Writes a human-readable message to stderr and returns an `ExitCode` carrying
/// the chosen status. Throw the result: `throw fail("…", code: .unknownDevice)`.
/// (`ExitCode` itself prints nothing, so the message isn't duplicated.)
func fail(_ message: String, code: ExitStatus) -> ExitCode {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    return ExitCode(code.rawValue)
}

// MARK: - Input kind

/// How `--input` is interpreted, decided by file extension. Videos route
/// through `VideoFrameCompositor`; everything else is treated as an image.
enum InputKind {
    case image
    case video

    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    init(path: String) {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        self = Self.videoExtensions.contains(ext) ? .video : .image
    }
}

/// Throws `.unreadableInput` when no file exists at `path`. Finder hides known
/// extensions by default, so when the path is missing an extension that does
/// exist on disk, the error suggests the real filename.
func requireFile(atPath path: String) throws {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else {
        var message = "No file exists at \(path)."
        let extensions = [
            "png", "PNG", "jpg", "jpeg", "JPG", "JPEG", "heic", "HEIC",
            "mov", "MOV", "mp4", "MP4", "m4v", "M4V",
        ]
        if let actual = extensions.map({ url.appendingPathExtension($0) })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            message += " Did you mean \(actual.path)? (Finder hides known file extensions by default.)"
        }
        throw fail(message, code: .unreadableInput)
    }
}

// MARK: - Image loading

/// Loads the `--input` image, distinguishing "no such file" from "file isn't a
/// readable image" so a caller can self-correct.
func loadInputImage(atPath path: String) throws -> CGImage {
    try requireFile(atPath: path)
    let url = URL(fileURLWithPath: path)
    guard let image = loadImage(at: url) else {
        throw fail(
            "Could not read \(path) as an image. Expected a PNG, JPEG, or HEIC file.",
            code: .unreadableInput
        )
    }
    return image
}

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

// MARK: - Video loading

/// Opens the `--input` video and returns the asset plus its display pixel size
/// (after the track's preferred transform, so a portrait iPhone recording
/// reports portrait dimensions).
func loadInputVideo(atPath path: String) async throws -> (asset: AVAsset, width: Int, height: Int) {
    try requireFile(atPath: path)
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    do {
        let size = try await VideoFrameCompositor.videoDimensions(asset: asset)
        return (asset, size.width, size.height)
    } catch {
        throw fail(
            "Could not read \(path) as a video. Expected a QuickTime or MP4 movie "
                + "(.mov, .mp4, .m4v) with a video track.",
            code: .unreadableInput
        )
    }
}

// MARK: - Output size

/// Resolves `--output-size` against the framed output's native size. Accepts a
/// bare width (`1920`), an exact size (`1920x988`, which must match the bezel's
/// aspect ratio), or a percentage (`50%`). Always preserves aspect, mirroring
/// the app's export-size behavior, including its dimension limits.
func resolveOutputSize(
    _ spec: String,
    nativeWidth: Int,
    nativeHeight: Int,
    isVideo: Bool
) throws -> (width: Int, height: Int) {
    let aspect = Double(nativeWidth) / Double(nativeHeight)
    let resolved: (width: Int, height: Int)

    if spec.hasSuffix("%") {
        guard let percent = Double(spec.dropLast()), percent > 0 else {
            throw fail(
                "Invalid --output-size '\(spec)'. Percentages look like 50% and must be positive.",
                code: .usage
            )
        }
        resolved = (
            width: max(1, Int((Double(nativeWidth) * percent / 100).rounded())),
            height: max(1, Int((Double(nativeHeight) * percent / 100).rounded()))
        )
    } else if let size = parseDimensions(spec) {
        let expectedHeight = max(1, Int((Double(size.width) / aspect).rounded()))
        guard abs(size.height - expectedHeight) <= 1 else {
            throw fail(
                "--output-size \(spec) does not match the framed output's aspect ratio "
                    + "(native \(nativeWidth)×\(nativeHeight)). For width \(size.width) "
                    + "the height is \(expectedHeight); pass just the width to have it computed.",
                code: .usage
            )
        }
        resolved = size
    } else if let width = Int(spec), width > 0 {
        resolved = (width: width, height: max(1, Int((Double(width) / aspect).rounded())))
    } else {
        throw fail(
            "Invalid --output-size '\(spec)'. Use a width (1920), a size (1920x988), "
                + "or a percentage (50%).",
            code: .usage
        )
    }

    // Same limits as the app's export-size sheet.
    let minDimension = 16
    let maxDimension = isVideo ? 7680 : 16384
    guard resolved.width >= minDimension, resolved.height >= minDimension else {
        throw fail(
            "--output-size \(spec) is too small: width and height must each be "
                + "at least \(minDimension) px (resolved to \(resolved.width)×\(resolved.height)).",
            code: .usage
        )
    }
    guard resolved.width <= maxDimension, resolved.height <= maxDimension else {
        throw fail(
            "--output-size \(spec) is too large: \(isVideo ? "video" : "image") width and "
                + "height must each be at most \(maxDimension) px "
                + "(resolved to \(resolved.width)×\(resolved.height)).",
            code: .usage
        )
    }
    return resolved
}

/// Scales a composited image to the target size with high-quality interpolation.
func scaleImage(_ image: CGImage, to size: (width: Int, height: Int)) -> CGImage? {
    guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(
              data: nil, width: size.width, height: size.height,
              bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
    return ctx.makeImage()
}

// MARK: - External tools

/// Finds an executable by walking PATH, mirroring shell lookup. Used to locate
/// ffmpeg for `--webm` before committing to a long export.
func findExecutable(_ name: String) -> URL? {
    guard let path = ProcessInfo.processInfo.environment["PATH"] else { return nil }
    for directory in path.split(separator: ":") where !directory.isEmpty {
        let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
        if FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
    }
    return nil
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
    /// "image" or "video".
    let kind: String
    let device: String
    let color: String
    let orientation: String
    let output: String
    let width: Int
    let height: Int
    /// Video only: true when the export is HEVC-with-alpha (.mov).
    let transparent: Bool?
    /// Path of the VP9/WebM copy when `--webm` ran.
    let webm: String?
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
