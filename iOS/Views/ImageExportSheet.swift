import SwiftUI

struct ImageExportSheet: View {
    @Bindable var model: ExportSizeModel
    var onCopy: () -> Void
    var onSaveToPhotos: () -> Void
    var onShare: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var validationAlert: ValidationAlert?

    private struct ValidationAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private var widthBinding: Binding<Int> {
        Binding(
            get: { model.width },
            set: { model.setWidthPreservingAspect($0) }
        )
    }

    private var heightBinding: Binding<Int> {
        Binding(
            get: { model.height },
            set: { model.setHeightPreservingAspect($0) }
        )
    }

    private var scaleBinding: Binding<Int> {
        Binding(
            get: { model.scale },
            set: { model.setScalePreservingAspect($0) }
        )
    }

    private func validated(_ action: @escaping () -> Void) {
        if let error = model.validationError {
            validationAlert = ValidationAlert(
                title: error.localizedDescription,
                message: error.localizedRecoverySuggestion ?? ""
            )
            return
        }
        dismiss()
        action()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Width")
                        Spacer()
                        TextField("Width", value: widthBinding, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .accessibilityLabel("Width")
                            .accessibilityHint("Export width in pixels")
                    }
                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("Height", value: heightBinding, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .accessibilityLabel("Height")
                            .accessibilityHint("Export height in pixels")
                    }
                    HStack {
                        Text("Scale")
                        Spacer()
                        TextField("Scale", value: scaleBinding, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .accessibilityLabel("Scale")
                            .accessibilityHint("Export scale as a percentage of the original size")
                        Text("%")
                    }
                } header: {
                    Text("Resolution")
                } footer: {
                    HStack {
                        Text("Original: \(model.originalWidth) \u{00d7} \(model.originalHeight)")
                        if model.sizeChanged {
                            Text("·")
                            Button("Reset") { model.reset() }
                                .accessibilityLabel("Reset Size")
                                .accessibilityHint("Resets to original image dimensions")
                        }
                    }
                }

                Section {
                    Button {
                        validated(onCopy)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    Button {
                        validated(onSaveToPhotos)
                    } label: {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        validated(onShare)
                    } label: {
                        Label("Share...", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .navigationTitle("Export Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(item: $validationAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .presentationDetents([.medium])
    }
}
