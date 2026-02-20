import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    @State private var showSavePanel = false
    @State private var optionKeyDown = false

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
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Open a screenshot or screen recording")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            .disabled(appState.isExporting)
                            .onChange(of: appState.videoBackgroundColor) {
                                appState.recomposite()
                            }

                        Button {
                            appState.rotateVideo(clockwise: !optionKeyDown)
                        } label: {
                            Image(systemName: optionKeyDown ? "rotate.left" : "rotate.right")
                        }
                        .help("Rotate video (hold Option for counter-clockwise)")
                        .disabled(appState.isExporting)

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
                        appState.showFileImporter = true
                    }
                    Spacer()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .onChange(of: appState.showFileImporter) { _, newValue in
            if newValue {
                appState.showOpenPanel()
            } else {
                appState.dismissOpenPanel()
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            appState.processFile(url: url)
            return true
        }
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                optionKeyDown = event.modifierFlags.contains(.option)
                return event
            }
        }
        .frame(minWidth: 400, minHeight: 350)
    }

    private func copyImage() {
        guard let composited = appState.compositedImage else { return }
        let nsImage = NSImage(cgImage: composited, size: NSSize(width: composited.width, height: composited.height))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
    }

    private func saveImage() {
        guard let composited = appState.compositedImage else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "framed-screenshot.png"

        if panel.runModal() == .OK, let url = panel.url {
            _ = FrameCompositor.savePNG(image: composited, to: url)
        }
    }

    private func exportVideo() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "framed-recording.mp4"

        if panel.runModal() == .OK, let url = panel.url {
            appState.exportVideo(to: url)
        }
    }
}
