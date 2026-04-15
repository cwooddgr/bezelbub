import SwiftUI

struct VideoExportSheet: View {
    @Bindable var model: ExportSizeModel
    var onExport: () -> Void
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
                } header: {
                    Text("Resolution")
                } footer: {
                    HStack {
                        Text("Original: \(model.originalWidth) \u{00d7} \(model.originalHeight)")
                        if model.sizeChanged {
                            Text("·")
                            Button("Reset") { model.reset() }
                                .accessibilityLabel("Reset Size")
                                .accessibilityHint("Resets to original video dimensions")
                        }
                    }
                }


            }
            .navigationTitle("Export Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        if let error = model.validationError {
                            validationAlert = ValidationAlert(
                                title: error.localizedDescription,
                                message: error.localizedRecoverySuggestion ?? ""
                            )
                            return
                        }
                        dismiss()
                        onExport()
                    }
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
        .presentationDetents([.medium, .large])
    }
}
