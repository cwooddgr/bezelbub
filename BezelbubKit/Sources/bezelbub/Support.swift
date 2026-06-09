import ArgumentParser
import BezelbubKit
import CoreGraphics
import Foundation

// MARK: - Orientation

enum Orientation: String, ExpressibleByArgument, CaseIterable {
    case portrait
    case landscape
    /// Infer from the screenshot's aspect (landscape if wider than tall).
    case auto
}

// MARK: - Exit codes

/// Stable, distinct exit codes so scripts and agents can branch on failure type
/// rather than parsing stderr text. 1 is reserved for ArgumentParser usage errors.
enum ExitStatus: Int32 {
    case usage = 1
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
