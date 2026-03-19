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

    /// Generates sample composited mockups for the empty state display.
    /// Returns up to two CGImages: an iPhone and an iPad framed with colorful gradients.
    static func generateSampleMockups(devices: [DeviceDefinition]) -> [CGImage] {
        var results: [CGImage] = []

        let specs: [(id: String, colors: [CGColor])] = [
            ("iphone17pro", [
                CGColor(srgbRed: 0.3, green: 0.4, blue: 1.0, alpha: 1.0),
                CGColor(srgbRed: 0.7, green: 0.2, blue: 0.9, alpha: 1.0),
            ]),
            ("ipadair11m2", [
                CGColor(srgbRed: 1.0, green: 0.5, blue: 0.2, alpha: 1.0),
                CGColor(srgbRed: 1.0, green: 0.3, blue: 0.5, alpha: 1.0),
            ]),
        ]

        for spec in specs {
            guard let device = devices.first(where: { $0.id == spec.id }),
                  let screenRegion = device.screenRegion,
                  let gradient = makeGradientImage(
                      width: Int(screenRegion.width),
                      height: Int(screenRegion.height),
                      colors: spec.colors
                  ),
                  let composited = composite(
                      screenshot: gradient,
                      device: device,
                      color: device.defaultColor,
                      isLandscape: false
                  )
            else { continue }
            results.append(composited)
        }

        return results
    }
}
