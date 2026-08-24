import SwiftUI
import FaderLabCore

/// An on-screen mirror of exactly what's being sent to the X-Touch's buttons, encoder
/// rings, and scribble strips — the surface's equivalent of `FaderBarsPreviewView` and
/// `PixelGridPreviewView`, so the light show can be previewed without the hardware
/// connected. Covers both halves of the surface: the 8 channel strips above, and the
/// right-hand control cluster (the "Other Buttons" show) as a dot grid below.
struct SurfacePreviewView: View {
    let frame: SurfaceFrame
    /// Multiplies every internal metric (cells, dots, rings, fonts, spacing). This is the
    /// crisp way to render larger in a wide column — `.scaleEffect` would rasterize and
    /// blur the 6-7pt scribble text.
    var scale: CGFloat = 1

    private var rightSectionColumns: Int { 13 } // 65 right-section notes lay out 13 x 5

    var body: some View {
        VStack(alignment: .leading, spacing: 7 * scale) {
            HStack(spacing: 6 * scale) {
                ForEach(0..<XTouchSurfaceProtocol.stripCount, id: \.self) { strip in
                    stripColumn(strip)
                }
            }
            rightSectionDots
        }
        .padding(8 * scale)
        .background(Theme.previewWell)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline))
    }

    /// The right-hand control cluster (notes 40+), one dot per button in note order. Not a
    /// physical-layout map of the panel — a density readout, so the "Other Buttons" picker
    /// has visible on-screen feedback even without the X-Touch connected.
    private var rightSectionDots: some View {
        let indices = XTouchSurfaceProtocol.rightSectionButtonIndices
        let rows = stride(from: 0, to: indices.count, by: rightSectionColumns).map {
            Array(indices[$0..<min($0 + rightSectionColumns, indices.count)])
        }
        return VStack(alignment: .leading, spacing: 3 * scale) {
            Text("OTHER BUTTONS")
                .font(.system(size: 6 * scale, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 3 * scale) {
                    ForEach(row, id: \.self) { index in
                        Circle()
                            .fill(dotColor(for: frame.buttons[index]))
                            .frame(width: 7 * scale, height: 7 * scale)
                    }
                }
            }
        }
    }

    private func stripColumn(_ strip: Int) -> some View {
        VStack(spacing: 5 * scale) {
            scribbleCell(strip)
            ringIndicator(strip)
            VStack(spacing: 3 * scale) {
                ForEach(Array(Self.dotZones.enumerated()), id: \.offset) { _, zone in
                    buttonDot(zone: zone, strip: strip)
                }
            }
        }
    }

    private static let dotZones: [XTouchSurfaceProtocol.ButtonZone] = [.rec, .solo, .mute, .select]

    private func scribbleCell(_ strip: Int) -> some View {
        let text = frame.scribbleTexts[strip]
        let background = color(for: frame.scribbleColors[strip])
        return VStack(spacing: 1 * scale) {
            Text(text.upper.isEmpty ? " " : text.upper)
            Text(text.lower.isEmpty ? " " : text.lower)
        }
        .font(.system(size: 7 * scale, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .frame(width: 30 * scale, height: 22 * scale)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 3 * scale))
        .shadow(color: background.opacity(0.5), radius: 4)
    }

    private func ringIndicator(_ strip: Int) -> some View {
        let ring = frame.rings[strip]
        return ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 3 * scale)
            Circle()
                .trim(from: 0, to: max(0.001, CGFloat(min(max(ring.position, 0), 11))) / 11)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 22 * scale, height: 22 * scale)
    }

    private func buttonDot(zone: XTouchSurfaceProtocol.ButtonZone, strip: Int) -> some View {
        let note = zone.notes[strip]
        let state = frame[buttonNote: note]
        return Circle()
            .fill(dotColor(for: state))
            .frame(width: 7 * scale, height: 7 * scale)
    }

    private func dotColor(for state: XTouchSurfaceProtocol.ButtonLEDState) -> Color {
        switch state {
        case .off: return Color.white.opacity(0.12)
        case .blink: return Color.yellow
        case .solid: return Color.red
        }
    }

    private func color(for scribbleColor: XTouchSurfaceProtocol.ScribbleColor) -> Color {
        switch scribbleColor {
        case .black: return Color.white.opacity(0.08)
        case .red: return .red
        case .green: return .green
        case .yellow: return .yellow
        case .blue: return .blue
        case .magenta: return .purple
        case .cyan: return .cyan
        case .white: return Color.white.opacity(0.85)
        }
    }
}

#Preview {
    SurfacePreviewView(frame: .allOff, scale: 1.3)
}
