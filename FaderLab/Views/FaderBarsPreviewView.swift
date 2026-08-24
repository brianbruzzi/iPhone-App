import SwiftUI
import FaderLabCore

/// An on-screen mirror of the 9 X-Touch fader positions (8 channel strips + master), so
/// fader patterns can be previewed and tested even without the physical hardware
/// connected.
///
/// Drawn as a single `Canvas` on purpose: the previous version was ~30 views (a
/// GeometryReader per bar) whose layout re-ran on every update, and that class of
/// per-frame layout work is exactly what starved the 60Hz MIDI tick timer and brought
/// the fader-motor buzz back in Round 7. A Canvas is one view — repaints are pure
/// drawing, no layout.
struct FaderBarsPreviewView: View {
    /// Exactly `XTouchProtocol.faderCount` values, 0...1.
    let values: [Double]
    /// Total height of the preview (bar area + the number labels under it).
    var barHeight: CGFloat = 140

    private static let labelStrip: CGFloat = 18
    private static let spacing: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            let count = max(values.count, 1)
            let barWidth = (size.width - Self.spacing * CGFloat(count - 1)) / CGFloat(count)
            let barAreaHeight = size.height - Self.labelStrip

            for (index, rawValue) in values.enumerated() {
                let x = CGFloat(index) * (barWidth + Self.spacing)
                let isMaster = index == XTouchProtocol.masterFaderIndex
                let fill = isMaster ? Theme.masterFader : Color.accentColor

                let value = clamped(rawValue)
                let height = barAreaHeight * CGFloat(value)
                let barRect = CGRect(x: x, y: barAreaHeight - height, width: barWidth, height: height)

                var barContext = context
                barContext.addFilter(.shadow(color: fill.opacity(0.55), radius: 6))
                barContext.fill(
                    Path(roundedRect: barRect, cornerRadius: 3),
                    with: .color(fill)
                )

                let label = Text(isMaster ? "M" : "\(index + 1)")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
                context.draw(
                    label,
                    at: CGPoint(x: x + barWidth / 2, y: barAreaHeight + Self.labelStrip / 2),
                    anchor: .center
                )
            }
        }
        .frame(height: barHeight)
        .padding(8)
        .background(Theme.previewWell)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline))
    }

    private func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

#Preview {
    FaderBarsPreviewView(values: [0.2, 0.4, 0.6, 0.8, 1.0, 0.8, 0.6, 0.4, 0.5])
        .frame(width: 320)
}
