import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState

    @State private var showSavePanel = false

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            // Preview area
            if let composited = appState.compositedImage {
                let nsImage = NSImage(cgImage: composited, size: NSSize(width: composited.width, height: composited.height))
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 600, maxHeight: 700)
                    .padding()
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
                    .frame(width: 400, height: 300)
            } else if let error = appState.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(error)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 400, height: 300)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Open a screenshot to get started")
                        .foregroundStyle(.secondary)
                }
                .frame(width: 400, height: 300)
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
                    }

                    Button("Copy") {
                        copyImage()
                    }
                    .keyboardShortcut("c", modifiers: .command)

                    Button("Save...") {
                        saveImage()
                    }
                    .keyboardShortcut("s", modifiers: .command)
                } else {
                    Spacer()
                    Button("Open Screenshot...") {
                        appState.showFileImporter = true
                    }
                    .keyboardShortcut("o", modifiers: .command)
                    Spacer()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .fileImporter(
            isPresented: $appState.showFileImporter,
            allowedContentTypes: [.png, .jpeg, .heic],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                appState.processFile(url: url)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            appState.processFile(url: url)
            return true
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
}
