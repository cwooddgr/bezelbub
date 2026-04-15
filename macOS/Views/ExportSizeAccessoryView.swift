import SwiftUI

struct ExportSizeAccessoryView: View {
    @Bindable var model: ExportSizeModel

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

    private func dimensionField(value: Binding<Int>, label: String, hint: String) -> some View {
        TextField("", value: value, format: .number)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .padding(4)
            .frame(width: 80)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.gray.opacity(0.4), lineWidth: 1)
            )
            .accessibilityLabel(label)
            .accessibilityHint(hint)
    }

    var body: some View {
        Grid(alignment: .trailing, verticalSpacing: 8) {
            GridRow {
                Text("Width:")
                dimensionField(value: widthBinding, label: "Width", hint: "Export width in pixels")
            }
            GridRow {
                Text("Height:")
                dimensionField(value: heightBinding, label: "Height", hint: "Export height in pixels")
            }
            GridRow {
                Text("Scale:")
                dimensionField(value: scaleBinding, label: "Scale", hint: "Export scale as a percentage of the original size")
                Text("%")
                    .gridColumnAlignment(.leading)
            }
        }
        .padding(12)
    }
}
