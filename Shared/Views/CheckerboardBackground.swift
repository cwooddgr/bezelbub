import SwiftUI

/// The classic light-grey transparency checkerboard, shown behind the preview
/// when a transparent export background is selected. Deliberately fixed light
/// colors (not theme-adaptive) — it represents "no pixels here", matching the
/// convention of every image editor.
struct CheckerboardBackground: View {
    var squareSize: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            let columns = Int(ceil(size.width / squareSize))
            let rows = Int(ceil(size.height / squareSize))
            for row in 0..<rows {
                for column in 0..<columns where (row + column) % 2 == 1 {
                    let square = CGRect(
                        x: CGFloat(column) * squareSize,
                        y: CGFloat(row) * squareSize,
                        width: squareSize,
                        height: squareSize
                    )
                    context.fill(Path(square), with: .color(Color(white: 0.87)))
                }
            }
        }
        .background(Color.white)
    }
}
