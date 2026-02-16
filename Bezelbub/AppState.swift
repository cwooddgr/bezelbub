import SwiftUI
import CoreGraphics
import ImageIO

@Observable
final class AppState {
    var devices: [DeviceDefinition] = []
    var selectedDevice: DeviceDefinition?
    var selectedColor: DeviceColor?
    var isLandscape = false
    var screenshotImage: CGImage?
    var compositedImage: CGImage?
    var matches: [DeviceMatcher.Match] = []
    var errorMessage: String?
    var showFileImporter = false
    var isCompositing = false

    init() {
        devices = ScreenRegionDetector.detectAll(devices: DeviceCatalog.allDevices)
    }

    func processFile(url: URL) {
        guard url.startAccessingSecurityScopedResource() || true else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            errorMessage = "Could not load image."
            return
        }

        // Force-realize pixel data while security-scoped access is still active.
        // CGImage loads data lazily, so without this the sandbox revokes access
        // before the background compositing thread reads the pixels.
        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: image.width, height: image.height,
                  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let realized = ({ () -> CGImage? in
                  ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                  return ctx.makeImage()
              })()
        else {
            errorMessage = "Could not load image."
            return
        }

        screenshotImage = realized
        errorMessage = nil

        let w = image.width
        let h = image.height

        matches = DeviceMatcher.match(screenshotWidth: w, screenshotHeight: h, devices: devices)

        if matches.isEmpty {
            errorMessage = "No matching device found for \(w)×\(h) screenshot."
            compositedImage = nil
            selectedDevice = nil
            selectedColor = nil
            return
        }

        let match = matches[0]
        selectDevice(match.device, isLandscape: match.isLandscape)
    }

    func selectDevice(_ device: DeviceDefinition, isLandscape: Bool) {
        selectedDevice = device
        self.isLandscape = isLandscape
        selectedColor = device.defaultColor
        recomposite()
    }

    func selectColor(_ color: DeviceColor) {
        selectedColor = color
        recomposite()
    }

    func recomposite() {
        guard let screenshot = screenshotImage,
              let device = selectedDevice,
              let color = selectedColor
        else { return }

        isCompositing = true
        let landscape = isLandscape
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = FrameCompositor.composite(
                screenshot: screenshot,
                device: device,
                color: color,
                isLandscape: landscape
            )
            DispatchQueue.main.async {
                self?.compositedImage = result
                self?.isCompositing = false
                if result == nil {
                    self?.errorMessage = "Failed to composite image."
                }
            }
        }
    }
}
