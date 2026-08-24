import SwiftUI
import FaderLabCore

/// An on-screen mirror of the 9 X-Touch fader positions (8 channel strips + master), so
/// fader patterns can be previewed and tested even without the physical hardware
/// connected.
struct FaderBarsPreviewView: View {
    /// Exactly `XTouchProtocol.faderCount` values, 0...1.
    let values: [Double]
    /// Height of the bar area — the faders column runs this tall (280) now that it has a
    /// full column to itself; the old compact card used 140.
    var barHeight: CGFloat = 140

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                VStack(spacing: 4) {
                    GeometryReader { proxy in
                        let fill = isMaster(index) ? Theme.masterFader : Color.accentColor
                        RoundedRectangle(cornerRadius: 3)
                            .fill(fill)
                            .shadow(color: fill.opacity(0.55), radius: 6)
                            .frame(height: proxy.size.height * CGFloat(clamped(value)))
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    Text(isMaster(index) ? "M" : "\(index + 1)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: barHeight)
        .padding(8)
        .background(Theme.previewWell)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline))
    }

    private func isMaster(_ index: Int) -> Bool {
        index == XTouchProtocol.masterFaderIndex
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
