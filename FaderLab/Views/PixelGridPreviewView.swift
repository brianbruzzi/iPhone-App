import SwiftUI
import FaderLabCore

/// An on-screen mirror of exactly what's being sent to the Launchpad X's 8x8 RGB grid, so
/// pixel-art patterns can be previewed and tested even without the physical hardware
/// connected.
struct PixelGridPreviewView: View {
    let grid: PixelGrid

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<8, id: \.self) { y in
                HStack(spacing: 3) {
                    ForEach(0..<8, id: \.self) { x in
                        let color = grid[x, y]
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(red: Double(color.r) / 255, green: Double(color.g) / 255, blue: Double(color.b) / 255))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    PixelGridPreviewView(grid: .allBlack)
        .frame(width: 220, height: 220)
}
