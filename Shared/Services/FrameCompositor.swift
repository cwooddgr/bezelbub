import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum FrameCompositor {
    static func composite(
        screenshot: CGImage,
        device: DeviceDefinition,
        color: DeviceColor,
        isLandscape: Bool,
        backgroundColor: CGColor? = nil
    ) -> CGImage? {
        let bezelFileName = device.bezelFileName(color: color, landscape: isLandscape)

        guard let bezelURL = ScreenRegionDetector.bezelURL(fileName: bezelFileName),
              let bezelSource = CGImageSourceCreateWithURL(bezelURL as CFURL, nil),
              let bezelImage = CGImageSourceCreateImageAtIndex(bezelSource, 0, nil)
        else {
            return nil
        }

        let bezelWidth = bezelImage.width
        let bezelHeight = bezelImage.height

        // Get screen region for current orientation
        let screenRegion: CGRect
        if isLandscape {
            let landscapeBezelFileName = device.bezelFileName(color: color, landscape: true)
            if let landscapeRegion = ScreenRegionDetector.screenRegion(forBezelFileName: landscapeBezelFileName) {
                screenRegion = landscapeRegion
            } else if let portraitRegion = device.screenRegion {
                screenRegion = CGRect(
                    x: portraitRegion.origin.y,
                    y: portraitRegion.origin.x,
                    width: portraitRegion.height,
                    height: portraitRegion.width
                )
            } else {
                return nil
            }
        } else {
            guard let portraitRegion = device.screenRegion else { return nil }
            screenRegion = portraitRegion
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil,
                width: bezelWidth,
                height: bezelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            return nil
        }

        // Step 0: Fill background if specified (e.g. video mode where alpha isn't supported)
        if let backgroundColor {
            ctx.setFillColor(backgroundColor)
            ctx.fill(CGRect(x: 0, y: 0, width: bezelWidth, height: bezelHeight))
        }

        // Step 1: Draw screenshot centered on screen region at native pixel size (no scaling).
        // For landscape-only devices (e.g. Apple TV), crop 1px from each side (left/right) so
        // the screenshot sits pixel-perfectly behind the screen hole; the bezel drawn on top
        // covers any sub-pixel edge differences.
        let screenshotToDraw: CGImage
        if device.landscapeOnly {
            // Scale up if screenshot is smaller than the screen region (e.g. 1080p → 4K 2× upscale)
            var base = screenshot
            if base.width < Int(screenRegion.width) {
                let scale = screenRegion.width / CGFloat(base.width)
                let targetSize = CGSize(width: screenRegion.width, height: CGFloat(base.height) * scale)
                if let scaled = resize(image: base, to: targetSize) { base = scaled }
            }
            // Crop 1px from left and right for pixel-perfect fit in the screen hole
            let cropRect = CGRect(x: 1, y: 0, width: base.width - 2, height: base.height)
            screenshotToDraw = base.cropping(to: cropRect) ?? base
        } else {
            screenshotToDraw = screenshot
        }
        let ssWidth = CGFloat(screenshotToDraw.width)
        let ssHeight = CGFloat(screenshotToDraw.height)
        // Clip to the exact screen hole shape (rounded corners) using a pixel-accurate mask
        let drawX = screenRegion.midX - ssWidth / 2.0
        let drawY = screenRegion.midY - ssHeight / 2.0
        let flippedY = CGFloat(bezelHeight) - drawY - ssHeight
        let drawRect = CGRect(x: drawX, y: flippedY, width: ssWidth, height: ssHeight)

        ctx.saveGState()
        if let screenMask = ScreenRegionDetector.screenMask(forBezelFileName: bezelFileName) {
            ctx.clip(to: CGRect(x: 0, y: 0, width: bezelWidth, height: bezelHeight), mask: screenMask)
        }
        ctx.draw(screenshotToDraw, in: drawRect)
        ctx.restoreGState()

        // Step 2: Draw bezel frame on top — covers rounded corners and blends anti-aliased edges
        ctx.draw(bezelImage, in: CGRect(x: 0, y: 0, width: bezelWidth, height: bezelHeight))

        return ctx.makeImage()
    }

    static func resize(image: CGImage, to size: CGSize) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    static func savePNG(image: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }

    /// Creates a diagonal linear gradient CGImage at the specified size.
    static func makeGradientImage(width: Int, height: Int, colors: [CGColor]) -> CGImage? {
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: nil)
        else { return nil }

        ctx.drawLinearGradient(
            gradient,
            start: .zero,
            end: CGPoint(x: width, y: height),
            options: []
        )
        return ctx.makeImage()
    }

    /// Generates a sample composited mockup for the empty state display:
    /// a MacBook, iPad, and iPhone in landscape, bottom-aligned and sized to their
    /// physical proportions, each overlapping the previous. Returns a single CGImage
    /// (wrapped in an array to match the existing call sites).
    static func generateSampleMockups(devices: [DeviceDefinition]) -> [CGImage] {
        struct Spec {
            let id: String
            let colors: [CGColor]
            let physicalWidthMM: Double  // horizontal size in chosen orientation
            let isLandscape: Bool
        }
        // Physical widths in the chosen orientation (from Apple specs):
        //   MacBook Pro 14" M5 landscape: 312.6 mm (long side)
        //   iPad Air 11" M2 portrait: 178.5 mm (short side)
        //   iPhone 17 Pro landscape: 150.0 mm (long side)
        let specs: [Spec] = [
            Spec(id: "macbookprom514", colors: [
                CGColor(srgbRed: 0.30, green: 0.45, blue: 1.00, alpha: 1.0),
                CGColor(srgbRed: 0.65, green: 0.20, blue: 0.90, alpha: 1.0),
            ], physicalWidthMM: 312.6, isLandscape: true),
            Spec(id: "ipadair11m2", colors: [
                CGColor(srgbRed: 1.00, green: 0.55, blue: 0.20, alpha: 1.0),
                CGColor(srgbRed: 1.00, green: 0.30, blue: 0.50, alpha: 1.0),
            ], physicalWidthMM: 178.5, isLandscape: false),
            Spec(id: "iphone17pro", colors: [
                CGColor(srgbRed: 0.20, green: 0.85, blue: 0.70, alpha: 1.0),
                CGColor(srgbRed: 0.25, green: 0.70, blue: 0.95, alpha: 1.0),
            ], physicalWidthMM: 150.0, isLandscape: true),
        ]

        struct Rendered {
            let image: CGImage
            let physicalWidthMM: Double
        }
        var items: [Rendered] = []
        for spec in specs {
            guard let device = devices.first(where: { $0.id == spec.id }) else { return [] }
            let color = device.defaultColor
            let bezelFileName = device.bezelFileName(color: color, landscape: spec.isLandscape)
            guard let region = ScreenRegionDetector.screenRegion(forBezelFileName: bezelFileName),
                  let gradient = makeGradientImage(
                      width: Int(region.width),
                      height: Int(region.height),
                      colors: spec.colors
                  ),
                  let composited = composite(
                      screenshot: gradient,
                      device: device,
                      color: color,
                      isLandscape: spec.isLandscape
                  )
            else { return [] }
            items.append(Rendered(image: composited, physicalWidthMM: spec.physicalWidthMM))
        }

        // mm → px scale, anchored so the first device (MacBook) is 1400 px wide.
        let scale = 1400.0 / items[0].physicalWidthMM
        let widths: [Double] = items.map { $0.physicalWidthMM * scale }
        let heights: [Double] = zip(items, widths).map { r, w in
            w * Double(r.image.height) / Double(r.image.width)
        }

        // Lay out left-to-right; each device overlaps the prior by a fraction of its own width.
        let overlapFractions: [Double] = [0, 0.40, 0.45]
        var xOffsets: [Double] = []
        var cursor: Double = 0
        for i in 0..<items.count {
            let x = i == 0 ? 0 : cursor - overlapFractions[i] * widths[i]
            xOffsets.append(x)
            cursor = x + widths[i]
        }
        let canvasWidth = Int(ceil(cursor))
        let canvasHeight = Int(ceil(heights.max() ?? 0))

        guard canvasWidth > 0, canvasHeight > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: canvasWidth,
                  height: canvasHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return [] }

        ctx.interpolationQuality = .high
        // CGContext origin is bottom-left, so drawing at y=0 bottom-aligns each device.
        for i in 0..<items.count {
            let rect = CGRect(x: xOffsets[i], y: 0, width: widths[i], height: heights[i])
            ctx.draw(items[i].image, in: rect)
        }
        guard let image = ctx.makeImage() else { return [] }
        return [image]
    }
}
