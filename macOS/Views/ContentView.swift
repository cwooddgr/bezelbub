import BezelbubKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState

    @State private var showSavePanel = false
    @State private var optionKeyDown = false
    @State private var eventMonitor: Any?
    @State private var sampleMockups: [CGImage] = []
    @State private var exportedVideoURL: URL?
    @State private var showTransparentExportInfo = false
    @AppStorage("suppressTransparentExportInfo") private var suppressTransparentExportInfo = false

    /// The exact conversion command offered after a transparent export —
    /// real paths, ready to paste into a terminal.
    private var ffmpegCommand: String {
        guard let url = exportedVideoURL else { return "" }
        let webm = url.deletingPathExtension().appendingPathExtension("webm")
        return "ffmpeg -i \"\(url.path)\" -c:v libvpx-vp9 -pix_fmt yuva420p \"\(webm.path)\""
    }

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            // Preview area
            ZStack {
                if let composited = appState.compositedImage {
                    let nsImage = NSImage(cgImage: composited, size: NSSize(width: composited.width, height: composited.height))
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .background {
                            if appState.isVideoMode && appState.videoBackgroundTransparent {
                                CheckerboardBackground()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                        .overlay(alignment: .bottomLeading) {
                            if appState.isVideoMode {
                                Text("Video")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                                    .padding(8)
                            }
                        }
                        .overlay {
                            if appState.isCompositing {
                                ProgressView()
                                    .controlSize(.large)
                                    .padding(20)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                } else if appState.isCompositing {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = appState.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(error)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 16) {
                        if !sampleMockups.isEmpty {
                            HStack(spacing: -20) {
                                ForEach(Array(sampleMockups.enumerated()), id: \.offset) { index, mockup in
                                    let nsImage = NSImage(cgImage: mockup, size: NSSize(width: mockup.width, height: mockup.height))
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                                        .zIndex(Double(sampleMockups.count - index))
                                }
                            }
                            .frame(maxHeight: 280)
                            .padding(.horizontal, 40)
                        }
                        Text("Frame your screenshots and screen recordings in Apple device bezels")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Text("Drop an image here, or press \u{2318}O")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task {
                        if sampleMockups.isEmpty {
                            sampleMockups = FrameCompositor.generateSampleMockups(devices: appState.devices)
                        }
                    }
                }

                // Export progress overlay
                if appState.isExporting {
                    ZStack {
                        Color.black.opacity(0.3)
                        VStack(spacing: 12) {
                            ProgressView(value: appState.exportProgress)
                                .frame(width: 200)
                            Text("\(Int(appState.exportProgress * 100))%")
                                .font(.headline.monospacedDigit())
                            Text("Exporting video...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }

            Divider()

            // Toolbar
            HStack {
                if let device = appState.selectedDevice {
                    // Device picker (for ambiguous matches)
                    if appState.matches.count > 1 {
                        Picker("Device", selection: Binding(
                            get: { device.id },
                            set: { newID in
                                if let match = appState.matches.first(where: { $0.device.id == newID }) {
                                    appState.selectDevice(match.device, isLandscape: match.isLandscape)
                                }
                            }
                        )) {
                            ForEach(appState.matches, id: \.device.id) { match in
                                Text(match.device.displayName).tag(match.device.id)
                            }
                        }
                        .frame(maxWidth: 180)
                        .disabled(appState.isExporting)
                    } else {
                        Text(device.displayName)
                            .fontWeight(.medium)
                    }

                    Spacer()

                    // Color picker
                    if device.colors.count > 1 {
                        Picker("Color", selection: Binding(
                            get: { appState.selectedColor?.id ?? "" },
                            set: { newID in
                                if let color = device.colors.first(where: { $0.id == newID }) {
                                    appState.selectColor(color)
                                }
                            }
                        )) {
                            ForEach(device.colors) { color in
                                Text(color.displayName).tag(color.id)
                            }
                        }
                        .frame(maxWidth: 180)
                        .disabled(appState.isExporting)
                    }

                    if appState.isVideoMode {
                        ColorPicker("Background", selection: $appState.videoBackgroundColor, supportsOpacity: false)
                            .disabled(appState.isExporting || appState.videoBackgroundTransparent)
                            .opacity(appState.videoBackgroundTransparent ? 0.4 : 1)
                            .onChange(of: appState.videoBackgroundColor) {
                                appState.recompositeDebounced()
                            }

                        Toggle("Transparent", isOn: $appState.videoBackgroundTransparent)
                            .disabled(appState.isExporting)
                            .help(
                                "Export HEVC with alpha (.mov). Plays in Safari and "
                                    + "Apple apps; convert to WebM for other browsers."
                            )
                            .onChange(of: appState.videoBackgroundTransparent) {
                                appState.recomposite()
                                if appState.videoBackgroundTransparent {
                                    NSColorPanel.shared.close()
                                }
                            }
                            .accessibilityLabel("Transparent Background")
                            .accessibilityHint("Exports HEVC with alpha as a QuickTime movie")

                        Button {
                            appState.rotateVideo(clockwise: !optionKeyDown)
                        } label: {
                            Image(systemName: optionKeyDown ? "rotate.left" : "rotate.right")
                        }
                        .help("Rotate video (hold Option for counter-clockwise)")
                        .disabled(appState.isExporting)
                        .accessibilityLabel("Rotate Video")
                        .accessibilityHint("Hold Option for counter-clockwise")

                        Button("Export Video...") {
                            exportVideo()
                        }
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(appState.isExporting)
                    } else {
                        Button("Copy") {
                            copyImage()
                        }
                        .keyboardShortcut("c", modifiers: .command)
                        .disabled(appState.isExporting)

                        Button("Save...") {
                            saveImage()
                        }
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(appState.isExporting)
                    }
                } else {
                    Spacer()
                    Button("Open...") {
                        appState.showOpenPanel()
                    }
                    Spacer()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(.bar)
        .onDrop(of: [.fileURL, .image, .url], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .onAppear {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                optionKeyDown = event.modifierFlags.contains(.option)
                return event
            }
            if !appState.isVideoMode {
                NSColorPanel.shared.close()
            }
        }
        .onDisappear {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
            eventMonitor = nil
        }
        .onChange(of: appState.isVideoMode) { _, isVideo in
            if !isVideo {
                NSColorPanel.shared.close()
            }
        }
        .onChange(of: appState.isExporting) { wasExporting, isExporting in
            if wasExporting && !isExporting && appState.errorMessage == nil
                && appState.videoBackgroundTransparent
                && !suppressTransparentExportInfo
                && exportedVideoURL != nil {
                showTransparentExportInfo = true
            }
        }
        .alert("Transparent Video Exported", isPresented: $showTransparentExportInfo) {
            Button("Copy ffmpeg Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ffmpegCommand, forType: .string)
            }
            Button("Done") {}
            Button("Don't Show Again") {
                suppressTransparentExportInfo = true
            }
        } message: {
            Text(
                "This video is HEVC with alpha (.mov). Transparency shows in "
                    + "Safari and Apple apps; Chrome and Firefox need a WebM (VP9) "
                    + "copy.\n\nConvert it by pasting this into Terminal "
                    + "(needs ffmpeg 8+, or use the bezelbub CLI's --webm flag):\n\n"
                    + ffmpegCommand
            )
        }
        .frame(minWidth: 400, minHeight: 350)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        let canLoadImage = provider.canLoadObject(ofClass: NSImage.self)

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    Task { @MainActor in
                        appState.processFile(url: url)
                    }
                } else if canLoadImage {
                    // Promised-file drags (e.g. Photos) don't resolve to a URL;
                    // fall back to loading the image data directly.
                    loadImageData(from: provider)
                } else {
                    showDropFallbackError()
                }
            }
            return true
        }

        if canLoadImage {
            loadImageData(from: provider)
            return true
        }

        showDropFallbackError()
        return false
    }

    private func loadImageData(from provider: NSItemProvider) {
        _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
            guard let nsImage = image as? NSImage,
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else {
                showDropFallbackError()
                return
            }
            Task { @MainActor in
                appState.processImage(cgImage: cgImage)
            }
        }
    }

    private func showDropFallbackError() {
        Task { @MainActor in
            appState.errorMessage = "Drag images from Finder, or use File > Open."
        }
    }

    private func copyImage() {
        guard let composited = appState.compositedImage else { return }
        let nsImage = NSImage(cgImage: composited, size: NSSize(width: composited.width, height: composited.height))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
    }

    private func saveImage() {
        guard let composited = appState.compositedImage else { return }

        let sizeModel = ExportSizeModel(width: composited.width, height: composited.height, mode: .image)
        let accessory = NSHostingView(rootView: ExportSizeAccessoryView(model: sizeModel))
        accessory.frame.size = accessory.fittingSize

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = (appState.sourceFileName ?? "screenshot") + "-framed.png"
        panel.directoryURL = appState.sourceDirectoryURL
        panel.accessoryView = accessory
        let delegate = ExportSizeValidator(model: sizeModel)
        panel.delegate = delegate

        if panel.runModal() == .OK, let url = panel.url {
            _ = delegate
            if sizeModel.sizeChanged {
                if let resized = FrameCompositor.resize(image: composited, to: sizeModel.targetSize) {
                    _ = FrameCompositor.savePNG(image: resized, to: url)
                }
            } else {
                _ = FrameCompositor.savePNG(image: composited, to: url)
            }
        }
    }

    private func exportVideo() {
        guard let composited = appState.compositedImage else { return }
        let transparent = appState.videoBackgroundTransparent

        let sizeModel = ExportSizeModel(width: composited.width, height: composited.height, mode: .video)
        let accessory = NSHostingView(rootView: ExportSizeAccessoryView(
            model: sizeModel,
            footnote: transparent
                ? "HEVC with alpha (.mov) — plays in Safari and Apple apps;\nconvert to WebM for other browsers."
                : nil
        ))
        accessory.frame.size = accessory.fittingSize

        let panel = NSSavePanel()
        panel.allowedContentTypes = [transparent ? .quickTimeMovie : .mpeg4Movie]
        panel.nameFieldStringValue = (appState.sourceFileName ?? "recording")
            + "-framed." + (transparent ? "mov" : "mp4")
        panel.directoryURL = appState.sourceDirectoryURL
        panel.accessoryView = accessory
        let delegate = ExportSizeValidator(model: sizeModel)
        panel.delegate = delegate

        if panel.runModal() == .OK, let url = panel.url {
            _ = delegate
            let size: CGSize? = sizeModel.sizeChanged ? sizeModel.targetSize : nil
            exportedVideoURL = url
            appState.exportVideo(to: url, size: size)
        }
    }
}

private final class ExportSizeValidator: NSObject, NSOpenSavePanelDelegate {
    let model: ExportSizeModel
    init(model: ExportSizeModel) { self.model = model }

    func panel(_ sender: Any, validate url: URL) throws {
        if let error = model.validationError { throw error }
    }
}
