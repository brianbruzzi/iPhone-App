import SwiftUI
import FaderLabCore

/// An on-screen mirror of exactly what's being sent to the X-Touch's buttons, encoder
/// rings, and scribble strips — the surface's equivalent of `FaderBarsPreviewView` and
/// `PixelGridPreviewView`, so the light show can be previewed without the hardware
/// connected.
struct SurfacePreviewView: View {
    let frame: SurfaceFrame

    private static let dotZones: [XTouchSurfaceProtocol.ButtonZone] = [.rec, .solo, .mute, .select]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<XTouchSurfaceProtocol.stripCount, id: \.self) { strip in
                stripColumn(strip)
            }
        }
        .padding(8)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func stripColumn(_ strip: Int) -> some View {
        VStack(spacing: 5) {
            scribbleCell(strip)
            ringIndicator(strip)
            VStack(spacing: 3) {
                ForEach(Array(Self.dotZones.enumerated()), id: \.offset) { _, zone in
                    buttonDot(zone: zone, strip: strip)
                }
            }
        }
    }

    private func scribbleCell(_ strip: Int) -> some View {
        let text = frame.scribbleTexts[strip]
        return VStack(spacing: 1) {
            Text(text.upper.isEmpty ? " " : text.upper)
            Text(text.lower.isEmpty ? " " : text.lower)
        }
        .font(.system(size: 7, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .frame(width: 30, height: 22)
        .background(color(for: frame.scribbleColors[strip]))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func ringIndicator(_ strip: Int) -> some View {
        let ring = frame.rings[strip]
        return ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.001, CGFloat(min(max(ring.position, 0), 11))) / 11)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 22, height: 22)
    }

    private func buttonDot(zone: XTouchSurfaceProtocol.ButtonZone, strip: Int) -> some View {
        let note = zone.notes[strip]
        let state = frame[buttonNote: note]
        return Circle()
            .fill(dotColor(for: state))
            .frame(width: 7, height: 7)
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
    SurfacePreviewView(frame: .allOff)
        .frame(width: 300)
}
