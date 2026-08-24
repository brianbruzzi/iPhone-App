import SwiftUI
import FaderLabCore

/// An on-screen mirror of exactly what's being sent to the Launchpad X's 8x8 RGB grid, so
/// pixel-art patterns can be previewed and tested even without the physical hardware
/// connected.
///
/// A single `Canvas` (not 64 shape views): repaints are pure drawing with zero layout,
/// which keeps the main thread free for the 60Hz MIDI tick — see FaderBarsPreviewView.
struct PixelGridPreviewView: View {
    let grid: PixelGrid

    private static let spacing: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let cell = (side - Self.spacing * 7) / 8
            let originX = (size.width - side) / 2
            let originY = (size.height - side) / 2

            for y in 0..<8 {
                for x in 0..<8 {
                    let color = grid[x, y]
                    let rect = CGRect(
                        x: originX + CGFloat(x) * (cell + Self.spacing),
                        y: originY + CGFloat(y) * (cell + Self.spacing),
                        width: cell,
                        height: cell
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 4),
                        with: .color(Color(
                            red: Double(color.r) / 255,
                            green: Double(color.g) / 255,
                            blue: Double(color.b) / 255
                        ))
                    )
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(8)
        .background(Theme.previewWell)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline))
        // One static ambient glow on the whole well — deliberately NOT per-cell shadows.
        .shadow(color: Color.accentColor.opacity(0.12), radius: 24)
    }
}

#Preview {
    PixelGridPreviewView(grid: .allBlack)
        .frame(width: 220, height: 220)
}
