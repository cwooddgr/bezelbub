import SwiftUI
import CoreGraphics
import ImageIO
import AVFoundation
import UniformTypeIdentifiers

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

    // Open panel (modeless, so drag-and-drop still works on the main window)
    @ObservationIgnored private var openPanel: NSOpenPanel?

    // Video state
    var videoAsset: AVAsset?
    var videoURL: URL?
    var isExporting = false
    var exportProgress: Double = 0
    var videoRotation: Int = 0  // Extra rotation in degrees (0, 90, 180, 270)
    var videoBackgroundColor: Color = .white
    var isVideoMode: Bool { videoAsset != nil }
    var sourceFileName: String?

    init() {
        devices = ScreenRegionDetector.detectAll(devices: DeviceCatalog.allDevices)
    }

    func processFile(url: URL) {
        showFileImporter = false
        dismissOpenPanel()
        sourceFileName = url.deletingPathExtension().lastPathComponent

        let ext = url.pathExtension.lowercased()
        if ["mov", "mp4", "m4v"].contains(ext) {
            processVideo(url: url)
        } else {
            processImage(url: url)
        }
    }

    func showOpenPanel() {
        guard openPanel == nil else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .movie, .mpeg4Movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        openPanel = panel

        panel.begin { [weak self] response in
            guard let self else { return }
            self.openPanel = nil
            self.showFileImporter = false
            if response == .OK, let url = panel.url {
                self.processFile(url: url)
            }
        }
    }

    func dismissOpenPanel() {
        openPanel?.cancel(nil)
        openPanel = nil
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
        videoRotation = 0

        _ = url.startAccessingSecurityScopedResource()
        // Store URL for security-scoped access during export (don't stop access yet)
        videoURL = url
        errorMessage = nil

        let asset = AVURLAsset(url: url)
        videoAsset = asset

        Task { @MainActor in
            await updateVideoMatch()
        }
    }

    func rotateVideo(clockwise: Bool) {
        videoRotation = (videoRotation + (clockwise ? 90 : 270)) % 360
        Task { @MainActor in
            await updateVideoMatch()
        }
    }

    private func updateVideoMatch() async {
        guard let asset = videoAsset else { return }

        do {
            let baseDims = try await VideoFrameCompositor.videoDimensions(asset: asset)

            // Swap dimensions for 90/270 degree extra rotation
            let swapped = videoRotation == 90 || videoRotation == 270
            let w = swapped ? baseDims.height : baseDims.width
            let h = swapped ? baseDims.width : baseDims.height

            matches = DeviceMatcher.match(
                screenshotWidth: w,
                screenshotHeight: h,
                devices: devices
            )

            if matches.isEmpty {
                errorMessage = "No matching device found for \(w)×\(h) video."
                selectedDevice = nil
                selectedColor = nil
                compositedImage = nil
                return
            }

            let match = matches[0]
            selectedDevice = match.device
            isLandscape = match.isLandscape
            selectedColor = match.device.defaultColor
            errorMessage = nil

            // Extract first frame and apply extra rotation for preview
            var frame = try await VideoFrameCompositor.firstFrame(asset: asset)
            if videoRotation != 0 {
                if let rotated = VideoFrameCompositor.rotateImage(frame, byDegrees: videoRotation) {
                    frame = rotated
                }
            }
            screenshotImage = frame
            recomposite()
        } catch {
            errorMessage = "Could not load video: \(error.localizedDescription)"
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
        let bgColor: CGColor? = isVideoMode ? NSColor(videoBackgroundColor).usingColorSpace(.sRGB)?.cgColor : nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = FrameCompositor.composite(
                screenshot: screenshot,
                device: device,
                color: color,
                isLandscape: landscape,
                backgroundColor: bgColor
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

    func exportVideo(to outputURL: URL, size: CGSize? = nil) {
        guard let asset = videoAsset,
              let device = selectedDevice,
              let color = selectedColor
        else { return }

        isExporting = true
        exportProgress = 0
        let landscape = isLandscape
        let rotation = videoRotation

        Task { @MainActor in
            do {
                try await VideoFrameCompositor.export(
                    asset: asset,
                    device: device,
                    color: color,
                    isLandscape: landscape,
                    extraRotation: rotation,
                    backgroundColor: NSColor(videoBackgroundColor).usingColorSpace(.sRGB)?.cgColor ?? CGColor(red: 1, green: 1, blue: 1, alpha: 1),
                    outputURL: outputURL,
                    outputSize: size
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
