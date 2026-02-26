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

    var body: some View {
        Grid(alignment: .trailing, verticalSpacing: 8) {
            GridRow {
                Text("Width:")
                TextField("", value: widthBinding, format: .number)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.tertiary))
                    .accessibilityLabel("Width")
                    .accessibilityHint("Export width in pixels")
            }
            GridRow {
                Text("Height:")
                TextField("", value: heightBinding, format: .number)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.tertiary))
                    .accessibilityLabel("Height")
                    .accessibilityHint("Export height in pixels")
            }
        }
        .padding(12)
    }
}
