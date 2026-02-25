import SwiftUI

@Observable
final class ExportSizeModel {
    static let minDimension = 1
    static let maxDimension = 16384
    static let highQualityPixelThreshold = 4_000_000

    let originalWidth: Int
    let originalHeight: Int
    let aspectRatio: Double // width / height

    var width: Int
    var height: Int

    init(width: Int, height: Int) {
        self.originalWidth = width
        self.originalHeight = height
        self.aspectRatio = Double(width) / Double(height)
        self.width = width
        self.height = height
    }

    var sizeChanged: Bool {
        width != originalWidth || height != originalHeight
    }

    var targetSize: CGSize {
        CGSize(width: width, height: height)
    }

    var isHighQuality: Bool {
        (width * height) <= Self.highQualityPixelThreshold
    }

    func reset() {
        width = originalWidth
        height = originalHeight
    }

    func setWidthPreservingAspect(_ newWidth: Int) {
        let w = Self.clamped(newWidth)
        width = w
        let newHeight = Self.clamped(Int((Double(w) / aspectRatio).rounded()))
        if newHeight != height {
            height = newHeight
        }
    }

    func setHeightPreservingAspect(_ newHeight: Int) {
        let h = Self.clamped(newHeight)
        height = h
        let newWidth = Self.clamped(Int((Double(h) * aspectRatio).rounded()))
        if newWidth != width {
            width = newWidth
        }
    }

    private static func clamped(_ value: Int) -> Int {
        min(max(value, minDimension), maxDimension)
    }
}
