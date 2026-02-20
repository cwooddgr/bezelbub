import SwiftUI
import CoreGraphics
import ImageIO
import AVFoundation

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

    // Video state
    var videoAsset: AVAsset?
    var videoURL: URL?
    var isExporting = false
    var exportProgress: Double = 0
    var isVideoMode: Bool { videoAsset != nil }

    init() {
        devices = ScreenRegionDetector.detectAll(devices: DeviceCatalog.allDevices)
    }

    func processFile(url: URL) {
        let ext = url.pathExtension.lowercased()
        if ["mov", "mp4", "m4v"].contains(ext) {
            processVideo(url: url)
        } else {
            processImage(url: url)
        }
    }

    private func processImage(url: URL) {
        // Clear video state
        videoAsset = nil
        videoURL = nil

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

    private func processVideo(url: URL) {
        // Clear image state
        screenshotImage = nil
        compositedImage = nil

        _ = url.startAccessingSecurityScopedResource()
        // Store URL for security-scoped access during export (don't stop access yet)
        videoURL = url
        errorMessage = nil

        let asset = AVURLAsset(url: url)
        videoAsset = asset

        Task { @MainActor in
            do {
                let dims = try await VideoFrameCompositor.videoDimensions(asset: asset)

                matches = DeviceMatcher.match(
                    screenshotWidth: dims.width,
                    screenshotHeight: dims.height,
                    devices: devices
                )

                if matches.isEmpty {
                    errorMessage = "No matching device found for \(dims.width)×\(dims.height) video."
                    selectedDevice = nil
                    selectedColor = nil
                    return
                }

                let match = matches[0]
                selectedDevice = match.device
                isLandscape = match.isLandscape
                selectedColor = match.device.defaultColor

                // Extract first frame for preview
                let frame = try await VideoFrameCompositor.firstFrame(asset: asset)
                screenshotImage = frame
                recomposite()
            } catch {
                errorMessage = "Could not load video: \(error.localizedDescription)"
            }
        }
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

    func exportVideo(to outputURL: URL) {
        guard let asset = videoAsset,
              let device = selectedDevice,
              let color = selectedColor
        else { return }

        isExporting = true
        exportProgress = 0
        let landscape = isLandscape

        Task { @MainActor in
            do {
                try await VideoFrameCompositor.export(
                    asset: asset,
                    device: device,
                    color: color,
                    isLandscape: landscape,
                    outputURL: outputURL
                ) { [weak self] progress in
                    self?.exportProgress = progress
                }
                isExporting = false
            } catch {
                isExporting = false
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}
