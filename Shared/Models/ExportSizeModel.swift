import SwiftUI

@Observable
final class ExportSizeModel: Identifiable {
    enum Mode {
        case image, video

        var minDimension: Int { 16 }

        var maxDimension: Int {
            switch self {
            case .image: return 16384
            case .video: return 7680
            }
        }

        var contentLabel: String {
            switch self {
            case .image: return "image"
            case .video: return "video"
            }
        }
    }

    let id = UUID()

    let mode: Mode
    let originalWidth: Int
    let originalHeight: Int
    let aspectRatio: Double // width / height

    var width: Int
    var height: Int

    init(width: Int, height: Int, mode: Mode) {
        self.mode = mode
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

    func reset() {
        width = originalWidth
        height = originalHeight
    }

    func setWidthPreservingAspect(_ newWidth: Int) {
        width = max(0, newWidth)
        guard width > 0 else { height = 0; return }
        let newHeight = max(1, Int((Double(width) / aspectRatio).rounded()))
        if newHeight != height { height = newHeight }
    }

    func setHeightPreservingAspect(_ newHeight: Int) {
        height = max(0, newHeight)
        guard height > 0 else { width = 0; return }
        let newWidth = max(1, Int((Double(height) * aspectRatio).rounded()))
        if newWidth != width { width = newWidth }
    }

    var scale: Int {
        Int((Double(width) / Double(originalWidth) * 100).rounded())
    }

    func setScalePreservingAspect(_ newScale: Int) {
        let s = max(0, newScale)
        width = Int((Double(originalWidth) * Double(s) / 100).rounded())
        height = Int((Double(originalHeight) * Double(s) / 100).rounded())
    }

    var validationError: NSError? {
        let minD = mode.minDimension
        let maxD = mode.maxDimension
        if width < minD || height < minD {
            return NSError(
                domain: "co.dgrlabs.bezelbub.ExportSize",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "The \(mode.contentLabel) size is too small.",
                    NSLocalizedRecoverySuggestionErrorKey: "Width and height must each be at least \(minD.formatted(.number)) pixels."
                ]
            )
        }
        if width > maxD || height > maxD {
            return NSError(
                domain: "co.dgrlabs.bezelbub.ExportSize",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "The \(mode.contentLabel) size is too large.",
                    NSLocalizedRecoverySuggestionErrorKey: "Width and height must each be at most \(maxD.formatted(.number)) pixels."
                ]
            )
        }
        return nil
    }
}
