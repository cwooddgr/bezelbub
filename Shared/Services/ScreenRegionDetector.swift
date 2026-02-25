import CoreGraphics
import Foundation
import ImageIO

enum ScreenRegionDetector {
    // MARK: - Bundled Regions (precomputed by Scripts/generate-screen-regions.swift)

    static let bundledRegions: [String: CGRect] = loadBundledRegions()

    private static func loadBundledRegions() -> [String: CGRect] {
        guard let url = Bundle.main.url(forResource: "screen-regions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: CodableRect].self, from: data)
        else {
            print("[Bezelbub] Warning: Could not load bundled screen-regions.json")
            return [:]
        }
        return dict.mapValues { $0.cgRect }
    }

    /// Look up a precomputed screen region by bezel filename.
    /// Falls back to runtime flood-fill if not found (should not happen with up-to-date JSON).
    static func screenRegion(forBezelFileName fileName: String) -> CGRect? {
        if let region = bundledRegions[fileName] {
            return region
        }
        print("[Bezelbub] Warning: No precomputed region for \(fileName), falling back to runtime detection")
        return detectScreenRegion(bezelFileName: fileName)
    }

    static func detectAll(devices: [DeviceDefinition]) -> [DeviceDefinition] {
        var devices = devices

        for i in devices.indices {
            let fileName = devices[i].bezelFileName(color: devices[i].defaultColor, landscape: false)
            if let region = screenRegion(forBezelFileName: fileName) {
                devices[i].screenRegion = region
            }
        }

        return devices
    }

    static func bezelURL(fileName: String) -> URL? {
        guard let bezelsURL = Bundle.main.url(forResource: "Bezels", withExtension: nil) else {
            return nil
        }
        let url = bezelsURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    static func detectScreenRegion(bezelFileName: String) -> CGRect? {
        guard let url = bezelURL(fileName: bezelFileName),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            print("[Bezelbub] Failed to load bezel: \(bezelFileName)")
            return nil
        }

        let width = image.width
        let height = image.height

        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data)
        else {
            return nil
        }

        let bytesPerPixel = image.bitsPerPixel / 8
        let bytesPerRow = image.bytesPerRow

        // Flood-fill from the center of the bezel image outward through
        // connected fully-transparent (alpha == 0) pixels. The center is
        // guaranteed to be in the screen area. The bounding box of all
        // filled pixels is the screen region.

        let startX = width / 2
        let startY = height / 2

        let startAlpha = ptr[startY * bytesPerRow + startX * bytesPerPixel + 3]
        guard startAlpha == 0 else {
            print("[Bezelbub] Center pixel is not transparent in \(bezelFileName)")
            return nil
        }

        var visited = [Bool](repeating: false, count: width * height)
        var stack: [(Int, Int)] = [(startX, startY)]

        var minX = startX, maxX = startX
        var minY = startY, maxY = startY

        while let (x, y) = stack.popLast() {
            guard x >= 0, x < width, y >= 0, y < height else { continue }
            let idx = y * width + x
            guard !visited[idx] else { continue }
            let alpha = ptr[y * bytesPerRow + x * bytesPerPixel + 3]
            guard alpha == 0 else { continue }

            visited[idx] = true

            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }

            stack.append((x - 1, y))
            stack.append((x + 1, y))
            stack.append((x, y - 1))
            stack.append((x, y + 1))
        }

        let rect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)

        guard rect.width > 100, rect.height > 100 else {
            return nil
        }

        return rect
    }

    // MARK: - Bundled Masks (precomputed by Scripts/generate-screen-regions.swift)

    /// Look up a precomputed screen mask by bezel filename.
    /// Falls back to runtime flood-fill if not found.
    static func screenMask(forBezelFileName fileName: String) -> CGImage? {
        if let mask = bundledMask(forBezelFileName: fileName) {
            return mask
        }
        print("[Bezelbub] Warning: No precomputed mask for \(fileName), falling back to runtime detection")
        return detectScreenMask(bezelFileName: fileName)
    }

    private static func bundledMask(forBezelFileName fileName: String) -> CGImage? {
        guard let masksURL = Bundle.main.url(forResource: "Masks", withExtension: nil) else {
            return nil
        }
        let url = masksURL.appendingPathComponent(fileName)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        return image
    }

    /// Returns a grayscale CGImage mask matching the exact screen hole shape
    /// (including rounded corners and anti-aliased edges) by flood-filling
    /// from the bezel center. White (0xFF) = screen area, black (0x00) = blocked.
    ///
    /// Phase 1 floods through fully-transparent (alpha==0) pixels to find the
    /// screen hole interior, collecting semi-transparent neighbors as edge
    /// candidates. Phase 2 expands into those semi-transparent pixels so the
    /// screenshot is fully visible behind them — the bezel drawn on top handles
    /// the actual alpha blending at the anti-aliased border.
    static func detectScreenMask(bezelFileName: String) -> CGImage? {
        guard let url = bezelURL(fileName: bezelFileName),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }

        let width = image.width
        let height = image.height

        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data)
        else {
            return nil
        }

        let bytesPerPixel = image.bitsPerPixel / 8
        let bytesPerRow = image.bytesPerRow

        let startX = width / 2
        let startY = height / 2

        let startAlpha = ptr[startY * bytesPerRow + startX * bytesPerPixel + 3]
        guard startAlpha == 0 else { return nil }

        // Phase 1: Flood fill through fully-transparent pixels from center.
        // When we hit a semi-transparent pixel (0 < alpha < 255), record it
        // as an edge candidate instead of stopping silently.
        var visited = [Bool](repeating: false, count: width * height)
        var stack: [(Int, Int)] = [(startX, startY)]
        var edgeCandidates: [(Int, Int)] = []

        while let (x, y) = stack.popLast() {
            guard x >= 0, x < width, y >= 0, y < height else { continue }
            let idx = y * width + x
            guard !visited[idx] else { continue }
            let alpha = ptr[y * bytesPerRow + x * bytesPerPixel + 3]
            if alpha != 0 {
                if alpha < 255 { edgeCandidates.append((x, y)) }
                continue
            }

            visited[idx] = true

            stack.append((x - 1, y))
            stack.append((x + 1, y))
            stack.append((x, y - 1))
            stack.append((x, y + 1))
        }

        // Phase 2: Expand into connected semi-transparent pixels at the
        // anti-aliased edge. These pixels need the screenshot at full opacity
        // behind them so the bezel's partial alpha blends correctly on top.
        // The expansion stops at fully-opaque (alpha==255) or fully-transparent
        // (alpha==0) pixels, so it can't leak into the outer transparent area.
        var edgeStack = edgeCandidates
        while let (x, y) = edgeStack.popLast() {
            guard x >= 0, x < width, y >= 0, y < height else { continue }
            let idx = y * width + x
            guard !visited[idx] else { continue }
            let alpha = ptr[y * bytesPerRow + x * bytesPerPixel + 3]
            guard alpha > 0, alpha < 255 else { continue }

            visited[idx] = true

            edgeStack.append((x - 1, y))
            edgeStack.append((x + 1, y))
            edgeStack.append((x, y - 1))
            edgeStack.append((x, y + 1))
        }

        // Build grayscale mask: visited = white (draw here), others = black
        var maskPixels = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            if visited[i] { maskPixels[i] = 0xFF }
        }

        // Create a regular grayscale CGImage (not an image mask).
        // clip(to:mask:) treats luminance as alpha: white = visible, black = clipped.
        let maskData = Data(maskPixels) as CFData
        guard let provider = CGDataProvider(data: maskData),
              let colorSpace = CGColorSpace(name: CGColorSpace.linearGray),
              let maskImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              )
        else {
            return nil
        }

        return maskImage
    }
}

struct CodableRect: Codable {
    let x, y, width, height: CGFloat

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    init(cgRect: CGRect) {
        x = cgRect.origin.x
        y = cgRect.origin.y
        width = cgRect.size.width
        height = cgRect.size.height
    }
}
