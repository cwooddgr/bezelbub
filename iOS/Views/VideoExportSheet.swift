import SwiftUI

struct VideoExportSheet: View {
    @Bindable var model: ExportSizeModel
    var onExport: () -> Void
    @Environment(\.dismiss) private var dismiss

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
                    }
                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("Height", value: heightBinding, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    if model.sizeChanged {
                        Button("Reset to Original") {
                            model.reset()
                        }
                    }
                } header: {
                    Text("Resolution")
                } footer: {
                    Text("Original: \(model.originalWidth) \u{00d7} \(model.originalHeight)")
                }

                Section("Quality") {
                    HStack(spacing: 12) {
                        Image(systemName: model.isHighQuality ? "checkmark.circle.fill" : "info.circle.fill")
                            .foregroundStyle(model.isHighQuality ? .green : .yellow)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.isHighQuality ? "High Quality" : "Standard Quality")
                                .fontWeight(.medium)
                            Text(model.isHighQuality ? "Best quality, smaller output" : "Good quality, faster export")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                        dismiss()
                        onExport()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
