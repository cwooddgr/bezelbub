import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum FrameCompositor {
    static func composite(
        screenshot: CGImage,
        device: DeviceDefinition,
        color: DeviceColor,
        isLandscape: Bool
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
            if let landscapeRegion = ScreenRegionDetector.detectScreenRegion(bezelFileName: landscapeBezelFileName) {
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

        // Step 1: Draw screenshot centered on screen region, at native pixel size (no scaling)
        // Clip to the exact screen hole shape (rounded corners) using a pixel-accurate mask
        let ssWidth = CGFloat(screenshot.width)
        let ssHeight = CGFloat(screenshot.height)
        let drawX = screenRegion.midX - ssWidth / 2.0
        let drawY = screenRegion.midY - ssHeight / 2.0
        let flippedY = CGFloat(bezelHeight) - drawY - ssHeight
        let drawRect = CGRect(x: drawX, y: flippedY, width: ssWidth, height: ssHeight)

        ctx.saveGState()
        if let screenMask = ScreenRegionDetector.detectScreenMask(bezelFileName: bezelFileName) {
            ctx.clip(to: CGRect(x: 0, y: 0, width: bezelWidth, height: bezelHeight), mask: screenMask)
        }
        ctx.draw(screenshot, in: drawRect)
        ctx.restoreGState()

        // Step 2: Draw bezel frame on top — covers rounded corners and blends anti-aliased edges
        ctx.draw(bezelImage, in: CGRect(x: 0, y: 0, width: bezelWidth, height: bezelHeight))

        return ctx.makeImage()
    }

    static func savePNG(image: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }
}
