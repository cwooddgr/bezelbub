import SwiftUI

final class ExportSizeModel: ObservableObject {
    static let minDimension = 1
    static let maxDimension = 16384

    let originalWidth: Int
    let originalHeight: Int
    let aspectRatio: Double // width / height

    @Published var width: Int
    @Published var height: Int

    init(width: Int, height: Int) {
        self.originalWidth = width
        self.originalHeight = height
        self.aspectRatio = Double(width) / Double(height)
        self.width = width
        self.height = height
    }

    var sizeChanged: Bool {
        width != originalWidth || height != originalHeight
    }

    var targetSize: CGSize {
        CGSize(width: width, height: height)
    }
}

struct ExportSizeAccessoryView: View {
    @ObservedObject var model: ExportSizeModel

    private func clamped(_ value: Int) -> Int {
        min(max(value, ExportSizeModel.minDimension), ExportSizeModel.maxDimension)
    }

    private var widthBinding: Binding<Int> {
        Binding(
            get: { model.width },
            set: { newWidth in
                let w = clamped(newWidth)
                model.width = w
                let newHeight = clamped(Int((Double(w) / model.aspectRatio).rounded()))
                if newHeight != model.height {
                    model.height = newHeight
                }
            }
        )
    }

    private var heightBinding: Binding<Int> {
        Binding(
            get: { model.height },
            set: { newHeight in
                let h = clamped(newHeight)
                model.height = h
                let newWidth = clamped(Int((Double(h) * model.aspectRatio).rounded()))
                if newWidth != model.width {
                    model.width = newWidth
                }
            }
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
            }
            GridRow {
                Text("Height:")
                TextField("", value: heightBinding, format: .number)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.tertiary))
            }
        }
        .padding(12)
    }
}
