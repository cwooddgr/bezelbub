import CoreGraphics

/// Empty space added evenly around a framed device, filled with the background
/// (or left clear). Applied at the bezel's native scale, before any output-size
/// scaling, so a percentage keeps the same proportions at every export size.
public enum FramePadding: Equatable, Sendable {
    /// A percentage of the bezel's longer side, added to each side.
    case percent(Double)
    /// An exact number of pixels at the bezel's native scale, added to each side.
    case pixels(Int)

    public static let none = FramePadding.pixels(0)

    /// Largest accepted percentage; keeps a typo from producing a huge canvas.
    public static let maxPercent: Double = 100

    /// Per-side padding in pixels for a bezel of the given size.
    public func pixels(forBezelWidth width: Int, height: Int) -> Int {
        switch self {
        case .percent(let percent):
            let clamped = min(max(percent, 0), Self.maxPercent)
            return Int((Double(max(width, height)) * clamped / 100).rounded())
        case .pixels(let pixels):
            return max(pixels, 0)
        }
    }

    /// Returns `image` centered on a canvas `padding` pixels larger on every
    /// side, with the margin filled with `backgroundColor` (clear when nil).
    public static func pad(_ image: CGImage, by padding: Int, backgroundColor: CGColor?) -> CGImage? {
        guard padding > 0 else { return image }
        let width = image.width + padding * 2
        let height = image.height + padding * 2
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
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

        if let backgroundColor {
            ctx.setFillColor(backgroundColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        ctx.draw(image, in: CGRect(x: padding, y: padding, width: image.width, height: image.height))
        return ctx.makeImage()
    }

    /// Returns a grayscale screen mask grown by `padding` pixels on every side,
    /// with the new margin black (blocked), so it lines up with a padded bezel.
    public static func padMask(_ mask: CGImage, by padding: Int) -> CGImage? {
        guard padding > 0 else { return mask }
        let width = mask.width + padding * 2
        let height = mask.height + padding * 2
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(mask, in: CGRect(x: padding, y: padding, width: mask.width, height: mask.height))
        return ctx.makeImage()
    }
}
