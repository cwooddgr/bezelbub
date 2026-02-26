import SwiftUI
import PhotosUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers

struct ShareItem: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct ContentView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showDocumentPicker = false
    @State private var shareItem: ShareItem?
    @State private var showSavedCheckmark = false
    @State private var saveError: String?
    @State private var photoSaveDelegate: PhotoSaveDelegate?
    @State private var exportedVideoURL: URL?
    @State private var exportSizeModel: ExportSizeModel?
    @State private var exportError: String?
    @State private var localBGColor: Color = .white
    @State private var bgColorDebounce: DispatchWorkItem?

    var body: some View {
        @Bindable var appState = appState

        NavigationStack {
            VStack(spacing: 0) {
                // Preview area
                ZStack {
                    if let composited = appState.compositedImage {
                        let uiImage = UIImage(cgImage: composited)
                        Image(uiImage: uiImage)
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
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("Open a screenshot or screen recording")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)

                            HStack(spacing: 12) {
                                Button {
                                    showPhotoPicker = true
                                } label: {
                                    Label("Photos", systemImage: "photo.on.rectangle")
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    showDocumentPicker = true
                                } label: {
                                    Label("Files", systemImage: "folder")
                                }
                                .buttonStyle(.bordered)
                            }
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

                if appState.selectedDevice != nil {
                    Divider()
                    controlsBar
                }
            }
            .navigationTitle("Bezelbub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            showPhotoPicker = true
                        } label: {
                            Label("Choose from Photos", systemImage: "photo.on.rectangle")
                        }

                        Button {
                            showDocumentPicker = true
                        } label: {
                            Label("Choose from Files", systemImage: "folder")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }

                if appState.compositedImage != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        if appState.isVideoMode {
                            Button {
                                guard let composited = appState.compositedImage else { return }
                                exportSizeModel = ExportSizeModel(
                                    width: composited.width,
                                    height: composited.height
                                )
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .disabled(appState.isExporting)
                        } else {
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
            }
            .overlay {
                if showSavedCheckmark {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showSavedCheckmark)
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadPhoto(from: newItem) }
            selectedPhotoItem = nil
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .any(of: [.screenshots, .images, .videos]))
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPickerView { url in
                appState.processFile(url: url)
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: item.items)
        }
        .sheet(item: $exportSizeModel) { model in
            VideoExportSheet(model: model) {
                performVideoExport(model: model)
            }
        }
        .onChange(of: appState.isExporting) { wasExporting, isExporting in
            if wasExporting && !isExporting {
                if let error = appState.errorMessage {
                    exportError = error
                    appState.errorMessage = nil
                } else if let url = exportedVideoURL {
                    shareItem = ShareItem(items: [url])
                }
            }
        }
        .alert("Export Failed", isPresented: .init(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .alert("Save Failed", isPresented: .init(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Controls Bar

    private var controlsBar: some View {
        @Bindable var appState = appState

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if let device = appState.selectedDevice {
                    // Device picker
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
                        .disabled(appState.isExporting)
                    } else {
                        Text(device.displayName)
                            .fontWeight(.medium)
                    }

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
                        .pickerStyle(.menu)
                        .disabled(appState.isExporting)
                    }

                    if appState.isVideoMode {
                        ColorPicker("BG", selection: $localBGColor, supportsOpacity: false)
                            .disabled(appState.isExporting)
                            .onAppear { localBGColor = appState.videoBackgroundColor }
                            .onChange(of: localBGColor) {
                                bgColorDebounce?.cancel()
                                let item = DispatchWorkItem {
                                    appState.videoBackgroundColor = localBGColor
                                    appState.recomposite()
                                }
                                bgColorDebounce = item
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
                            }

                        Button {
                            appState.rotateVideo(clockwise: true)
                        } label: {
                            Image(systemName: "rotate.right")
                        }
                        .disabled(appState.isExporting)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Photo Loading

    private func loadPhoto(from item: PhotosPickerItem) async {
        // Try loading as video first
        if let videoData = try? await item.loadTransferable(type: VideoFileTransferable.self) {
            await MainActor.run {
                appState.processFile(url: videoData.url)
            }
            return
        }

        // Load as image data
        guard let data = try? await item.loadTransferable(type: Data.self),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            await MainActor.run {
                appState.errorMessage = "Could not load the selected image."
            }
            return
        }

        await MainActor.run {
            appState.processImage(cgImage: cgImage)
        }
    }

    // MARK: - Actions

    private func copyImage() {
        guard let composited = appState.compositedImage else { return }
        let uiImage = UIImage(cgImage: composited)
        UIPasteboard.general.image = uiImage
    }

    private func saveToPhotos() {
        guard let composited = appState.compositedImage else { return }
        let uiImage = UIImage(cgImage: composited)
        let delegate = PhotoSaveDelegate { [self] error in
            photoSaveDelegate = nil
            if let error {
                saveError = error.localizedDescription
            } else {
                showSavedCheckmark = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    showSavedCheckmark = false
                }
            }
        }
        photoSaveDelegate = delegate
        UIImageWriteToSavedPhotosAlbum(uiImage, delegate, #selector(PhotoSaveDelegate.image(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    private func performVideoExport(model: ExportSizeModel) {
        guard appState.compositedImage != nil else { return }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent((appState.sourceFileName ?? "recording") + "-framed")
            .appendingPathExtension("mp4")

        // Remove existing temp file
        try? FileManager.default.removeItem(at: tempURL)

        exportedVideoURL = tempURL

        let size: CGSize? = model.sizeChanged ? model.targetSize : nil
        appState.exportVideo(to: tempURL, size: size, exportPreset: AVAssetExportPresetHighestQuality)
    }
}

// MARK: - Video File Transferable

struct VideoFileTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            // Copy to temp directory so it persists beyond the transfer
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(received.file.lastPathComponent)
            try? FileManager.default.removeItem(at: tempURL)
            try FileManager.default.copyItem(at: received.file, to: tempURL)
            return VideoFileTransferable(url: tempURL)
        }
    }
}

// MARK: - Document Picker

struct DocumentPickerView: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.png, .jpeg, .heic, .movie, .mpeg4Movie]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

// MARK: - Photo Save Delegate

class PhotoSaveDelegate: NSObject {
    let completion: (Error?) -> Void

    init(completion: @escaping (Error?) -> Void) {
        self.completion = completion
    }

    @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        DispatchQueue.main.async {
            self.completion(error)
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
