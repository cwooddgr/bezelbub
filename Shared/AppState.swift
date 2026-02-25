import SwiftUI
import CoreGraphics
import ImageIO
#if !SHARE_EXTENSION
import AVFoundation
#endif
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

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
    var isCompositing = false

    #if os(macOS)
    // Open panel (modeless, so drag-and-drop still works on the main window)
    @ObservationIgnored private var openPanel: NSOpenPanel?
    @ObservationIgnored var ensureWindowVisible: (() -> Void)?
    #endif
    @ObservationIgnored private var debounceWork: DispatchWorkItem?

    #if !SHARE_EXTENSION
    // Video state
    var videoAsset: AVAsset?
    var videoURL: URL?
    var isExporting = false
    var exportProgress: Double = 0
    var videoRotation: Int = 0  // Extra rotation in degrees (0, 90, 180, 270)
    var videoBackgroundColor: Color = .white
    var isVideoMode: Bool { videoAsset != nil }
    #endif
    var sourceFileName: String?
    var sourceDirectoryURL: URL?

    init() {
        devices = ScreenRegionDetector.detectAll(devices: DeviceCatalog.allDevices)

        #if DEBUG
        // Verify every bezel has a precomputed screen region
        let regions = ScreenRegionDetector.bundledRegions
        for device in devices {
            for color in device.colors {
                for landscape in [false, true] {
                    let fileName = device.bezelFileName(color: color, landscape: landscape)
                    assert(regions[fileName] != nil, "Missing precomputed screen region for \(fileName)")
                }
            }
        }
        #endif
    }

    func processFile(url: URL) {
        #if os(macOS)
        dismissOpenPanel()
        #endif
        sourceFileName = url.deletingPathExtension().lastPathComponent
        sourceDirectoryURL = url.deletingLastPathComponent()

        #if !SHARE_EXTENSION
        let ext = url.pathExtension.lowercased()
        if ["mov", "mp4", "m4v"].contains(ext) {
            processVideo(url: url)
        } else {
            processImage(url: url)
        }
        #else
        processImage(url: url)
        #endif
    }

    #if os(macOS)
    func showOpenPanel() {
        if let existing = openPanel {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .movie, .mpeg4Movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        openPanel = panel

        panel.begin { [weak self] response in
            guard let self else { return }
            self.openPanel = nil
            if response == .OK, let url = panel.url {
                // Ensure the app has a visible window before processing.
                // After Cmd-W closes the only window, there's nowhere to show results.
                if !NSApp.windows.contains(where: { $0.isVisible && !($0 is NSPanel) }) {
                    self.ensureWindowVisible?()
                }
                self.processFile(url: url)
            }
        }
    }

    func dismissOpenPanel() {
        openPanel?.cancel(nil)
        openPanel = nil
    }
    #endif

    #if !SHARE_EXTENSION
    private func stopVideoAccess() {
        videoURL?.stopAccessingSecurityScopedResource()
        videoURL = nil
    }
    #endif

    func processImage(url: URL) {
        #if !SHARE_EXTENSION
        // Clear video state
        videoAsset = nil
        stopVideoAccess()
        #endif

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
            errorMessage = "No matching device found for \(w)\u{00d7}\(h) screenshot."
            compositedImage = nil
            selectedDevice = nil
            selectedColor = nil
            return
        }

        let match = matches[0]
        selectDevice(match.device, isLandscape: match.isLandscape)
    }

    func processImage(cgImage: CGImage) {
        #if !SHARE_EXTENSION
        // Clear video state
        videoAsset = nil
        stopVideoAccess()
        #endif

        screenshotImage = cgImage
        errorMessage = nil
        sourceFileName = nil
        sourceDirectoryURL = nil

        let w = cgImage.width
        let h = cgImage.height

        matches = DeviceMatcher.match(screenshotWidth: w, screenshotHeight: h, devices: devices)

        if matches.isEmpty {
            errorMessage = "No matching device found for \(w)\u{00d7}\(h) screenshot."
            compositedImage = nil
            selectedDevice = nil
            selectedColor = nil
            return
        }

        let match = matches[0]
        selectDevice(match.device, isLandscape: match.isLandscape)
    }

    #if !SHARE_EXTENSION
    private func processVideo(url: URL) {
        // Clear image state
        screenshotImage = nil
        compositedImage = nil
        videoRotation = 0

        // Release previous video's security-scoped access before starting new one
        stopVideoAccess()
        _ = url.startAccessingSecurityScopedResource()
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
                errorMessage = "No matching device found for \(w)\u{00d7}\(h) video."
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
    #endif

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

    func recompositeDebounced() {
        debounceWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.recomposite()
        }
        debounceWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    #if !SHARE_EXTENSION
    private func videoBackgroundCGColor() -> CGColor {
        #if os(macOS)
        return NSColor(videoBackgroundColor).usingColorSpace(.sRGB)?.cgColor
            ?? CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        #elseif os(iOS)
        return UIColor(videoBackgroundColor).cgColor
        #endif
    }
    #endif

    func recomposite() {
        guard let screenshot = screenshotImage,
              let device = selectedDevice,
              let color = selectedColor
        else { return }

        isCompositing = true
        let landscape = isLandscape
        #if !SHARE_EXTENSION
        let bgColor: CGColor? = isVideoMode ? videoBackgroundCGColor() : nil
        #else
        let bgColor: CGColor? = nil
        #endif
        #if os(macOS)
        let compositingQoS = DispatchQoS.QoSClass.userInitiated
        #else
        let compositingQoS = DispatchQoS.QoSClass.utility
        #endif
        DispatchQueue.global(qos: compositingQoS).async { [weak self] in
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

    #if !SHARE_EXTENSION
    func exportVideo(to outputURL: URL, size: CGSize? = nil, exportPreset: String? = nil) {
        guard let asset = videoAsset,
              let device = selectedDevice,
              let color = selectedColor
        else { return }

        isExporting = true
        exportProgress = 0
        let landscape = isLandscape
        let rotation = videoRotation
        let bgColor = videoBackgroundCGColor()

        Task { @MainActor in
            do {
                try await VideoFrameCompositor.export(
                    asset: asset,
                    device: device,
                    color: color,
                    isLandscape: landscape,
                    extraRotation: rotation,
                    backgroundColor: bgColor,
                    outputURL: outputURL,
                    outputSize: size,
                    exportPreset: exportPreset
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
    #endif
}
