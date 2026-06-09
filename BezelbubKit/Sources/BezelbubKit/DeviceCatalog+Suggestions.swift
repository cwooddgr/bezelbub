import CoreGraphics
import Foundation

// Fuzzy lookups shared by headless front ends (the `bezelbub` CLI and the
// future MCP server) so a failed exact match comes back as actionable
// suggestions instead of a bare error.

public extension DeviceCatalog {
    /// Devices whose id or display name plausibly matches `query`: exact
    /// (case/punctuation-insensitive) first, then substring hits, then close
    /// edit-distance matches. Returns at most `limit`, best first.
    static func suggestDevices(
        matching query: String,
        in devices: [DeviceDefinition],
        limit: Int = 5
    ) -> [DeviceDefinition] {
        rank(query: query, candidates: devices, limit: limit) { [$0.id, $0.displayName] }
    }

    /// Colors of `device` that plausibly match `query`, for "did you mean"
    /// errors. Same ranking rules as `suggestDevices(matching:in:limit:)`.
    static func suggestColors(
        matching query: String,
        in device: DeviceDefinition,
        limit: Int = 3
    ) -> [DeviceColor] {
        rank(query: query, candidates: device.colors, limit: limit) { [$0.id, $0.displayName] }
    }

    private static func rank<T>(
        query: String,
        candidates: [T],
        limit: Int,
        names: (T) -> [String]
    ) -> [T] {
        let needle = normalized(query)
        guard !needle.isEmpty else { return [] }

        let scored: [(candidate: T, score: Int, index: Int)] = candidates.enumerated()
            .compactMap { index, candidate in
                var best: Int?
                for name in names(candidate).map(normalized) {
                    let score: Int?
                    if name == needle {
                        score = 0
                    } else if name.contains(needle) || needle.contains(name) {
                        score = 1
                    } else {
                        let distance = editDistance(needle, name)
                        // Tolerate roughly one typo per three characters.
                        score = distance <= max(2, needle.count / 3) ? 10 + distance : nil
                    }
                    if let score { best = min(best ?? .max, score) }
                }
                return best.map { (candidate, $0, index) }
            }

        return scored
            .sorted { $0.score != $1.score ? $0.score < $1.score : $0.index < $1.index }
            .prefix(limit)
            .map(\.candidate)
    }

    /// Lowercases and strips everything but letters/digits so
    /// "iPhone 17 Pro" matches "iphone17pro".
    private static func normalized(_ string: String) -> String {
        string.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Levenshtein distance.
    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}

public extension DeviceMatcher {
    /// When `match(screenshotWidth:screenshotHeight:devices:)` finds nothing,
    /// ranks devices by how close their screen aspect ratio is to the
    /// screenshot's, so callers can say "no exact match — nearest are…".
    /// Devices that can't take the screenshot's orientation (portrait capture
    /// vs. landscape-only bezel) are excluded.
    static func nearest(
        screenshotWidth: Int,
        screenshotHeight: Int,
        devices: [DeviceDefinition],
        limit: Int = 5
    ) -> [Match] {
        let isLandscape = screenshotWidth > screenshotHeight
        let longSide = Double(max(screenshotWidth, screenshotHeight))
        let shortSide = Double(min(screenshotWidth, screenshotHeight))
        guard shortSide > 0 else { return [] }
        let aspect = longSide / shortSide

        return devices
            .compactMap { device -> (match: Match, aspectError: Double)? in
                guard let region = device.screenRegion,
                      isLandscape || device.hasPortraitBezel
                else { return nil }
                let regionAspect = Double(max(region.width, region.height))
                    / Double(min(region.width, region.height))
                let error = abs(aspect - regionAspect) / regionAspect
                return (Match(device: device, isLandscape: isLandscape), error)
            }
            .sorted { $0.aspectError < $1.aspectError }
            .prefix(limit)
            .map(\.match)
    }
}
