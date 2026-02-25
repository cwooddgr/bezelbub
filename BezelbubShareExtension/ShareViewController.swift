import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CoreGraphics
import ImageIO

class ShareViewController: UIViewController {
    private var appState: AppState?
    private var hostingController: UIHostingController<AnyView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        let state = AppState()
        self.appState = state

        let shareView = ShareExtensionView(appState: state) { [weak self] in
            self?.close()
        }

        let hosting = UIHostingController(rootView: AnyView(shareView.environment(state)))
        hostingController = hosting
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hosting.didMove(toParent: self)

        loadSharedImage(into: state)
    }

    private func loadSharedImage(into state: AppState) {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            state.errorMessage = "No items received."
            return
        }

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.image.identifier) { [weak self] item, error in
                        Task { @MainActor in
                            self?.handleImageItem(item, state: state)
                        }
                    }
                    return
                }
            }
        }

        state.errorMessage = "No supported image found."
    }

    @MainActor
    private func handleImageItem(_ item: NSSecureCoding?, state: AppState) {
        if let url = item as? URL {
            state.processFile(url: url)
        } else if let uiImage = item as? UIImage, let cgImage = uiImage.cgImage {
            state.processImage(cgImage: cgImage)
        } else if let data = item as? Data,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            state.processImage(cgImage: cgImage)
        } else {
            state.errorMessage = "Could not load the shared image."
        }
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

// MARK: - Share Extension SwiftUI View

struct ShareExtensionView: View {
    let appState: AppState
    let onClose: () -> Void

    @State private var copiedNotice = false
    @State private var savedNotice = false
    @State private var shareItem: ShareItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Preview
                ZStack {
                    if let composited = appState.compositedImage {
                        let uiImage = UIImage(cgImage: composited)
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
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
                        ProgressView("Loading...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                if appState.selectedDevice != nil {
                    Divider()
                    controlsBar
                }
            }
            .navigationTitle("Bezelbub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onClose() }
                }

                if appState.compositedImage != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Menu {
                            Button {
                                copyImage()
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }

                            Button {
                                saveToPhotos()
                            } label: {
                                Label("Save to Photos", systemImage: "square.and.arrow.down")
                            }

                            Button {
                                if let composited = appState.compositedImage {
                                    shareItem = ShareItem(items: [UIImage(cgImage: composited)])
                                }
                            } label: {
                                Label("Share...", systemImage: "square.and.arrow.up")
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .overlay(alignment: .top) {
                if copiedNotice {
                    Text("Copied!")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 4)
                }
                if savedNotice {
                    Text("Saved!")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 4)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: copiedNotice)
            .animation(.easeInOut(duration: 0.2), value: savedNotice)
            .sheet(item: $shareItem) { item in
                ShareSheet(items: item.items)
            }
        }
    }

    private var controlsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if let device = appState.selectedDevice {
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
                        .pickerStyle(.menu)
                    } else {
                        Text(device.displayName)
                            .fontWeight(.medium)
                    }

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
                        .pickerStyle(.menu)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    private func copyImage() {
        guard let composited = appState.compositedImage else { return }
        let uiImage = UIImage(cgImage: composited)
        UIPasteboard.general.image = uiImage
        copiedNotice = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedNotice = false
        }
    }

    private func saveToPhotos() {
        guard let composited = appState.compositedImage else { return }
        let uiImage = UIImage(cgImage: composited)
        UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
        savedNotice = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            savedNotice = false
        }
    }
}

// MARK: - Share Sheet Types

struct ShareItem: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
