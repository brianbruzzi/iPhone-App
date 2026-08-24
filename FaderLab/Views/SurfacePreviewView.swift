import SwiftUI
import FaderLabCore

/// An on-screen mirror of exactly what's being sent to the X-Touch's buttons, encoder
/// rings, and scribble strips — the surface's equivalent of `FaderBarsPreviewView` and
/// `PixelGridPreviewView`, so the light show can be previewed without the hardware
/// connected. Covers both halves of the surface: the 8 channel strips above, and the
/// right-hand control cluster (the "Other Buttons" show) as a dot grid below.
///
/// A single `Canvas` on purpose: the previous version was ~250 views (every dot, ring,
/// and scribble cell its own view) whose layout re-ran on every frame — the main
/// contributor to the layout storm that starved the 60Hz MIDI tick and brought the
/// fader-motor buzz back in Round 7. As a Canvas, repaints are pure drawing.
struct SurfacePreviewView: View {
    let frame: SurfaceFrame
    /// Multiplies every internal metric (cells, dots, rings, fonts, spacing) so the view
    /// renders crisply at larger sizes — text is laid out at the final size, not
    /// rasterize-scaled.
    var scale: CGFloat = 1

    // Base (scale = 1) metrics. Total canvas size derives from these.
    private static let pad: CGFloat = 8
    private static let cellW: CGFloat = 30
    private static let cellH: CGFloat = 22
    private static let stripSpacing: CGFloat = 6
    private static let ringSize: CGFloat = 22
    private static let dot: CGFloat = 7
    private static let dotSpacing: CGFloat = 3
    private static let sectionGap: CGFloat = 7
    private static let dotColumns = 13 // 65 right-section notes lay out 13 x 5

    private static let dotZones: [XTouchSurfaceProtocol.ButtonZone] = [.rec, .solo, .mute, .select]

    private var canvasWidth: CGFloat {
        (Self.pad * 2 + Self.cellW * 8 + Self.stripSpacing * 7) * scale
    }

    private var canvasHeight: CGFloat {
        let strips = Self.cellH + 5 + Self.ringSize + 5 + Self.dot * 4 + Self.dotSpacing * 3
        let rightRows = ceil(CGFloat(XTouchSurfaceProtocol.rightSectionButtonIndices.count) / CGFloat(Self.dotColumns))
        let rightBlock = 10 + Self.dot * rightRows + Self.dotSpacing * (rightRows - 1)
        return (Self.pad * 2 + strips + Self.sectionGap + rightBlock) * scale
    }

    var body: some View {
        Canvas { context, _ in
            let s = scale
            var y = Self.pad * s

            // Channel strips: scribble cell, encoder ring, REC/SOLO/MUTE/SELECT dots.
            for strip in 0..<XTouchSurfaceProtocol.stripCount {
                let x = (Self.pad + CGFloat(strip) * (Self.cellW + Self.stripSpacing)) * s
                let centerX = x + Self.cellW * s / 2

                // Scribble cell with its glow.
                let cellRect = CGRect(x: x, y: y, width: Self.cellW * s, height: Self.cellH * s)
                let cellColor = color(for: frame.scribbleColors[strip])
                var cellContext = context
                cellContext.addFilter(.shadow(color: cellColor.opacity(0.5), radius: 4))
                cellContext.fill(Path(roundedRect: cellRect, cornerRadius: 3 * s), with: .color(cellColor))

                let text = frame.scribbleTexts[strip]
                for (line, string) in [text.upper, text.lower].enumerated() where !string.isEmpty {
                    context.draw(
                        Text(string)
                            .font(.system(size: 7 * s, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white),
                        at: CGPoint(x: centerX, y: cellRect.midY + (line == 0 ? -4.5 : 4.5) * s),
                        anchor: .center
                    )
                }

                // Encoder ring.
                let ring = frame.rings[strip]
                let ringCenter = CGPoint(x: centerX, y: y + (Self.cellH + 5 + Self.ringSize / 2) * s)
                let radius = (Self.ringSize / 2 - 1.5) * s
                context.stroke(
                    Path { $0.addArc(center: ringCenter, radius: radius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false) },
                    with: .color(Color.white.opacity(0.15)),
                    lineWidth: 3 * s
                )
                let fraction = max(0.001, Double(min(max(ring.position, 0), 11))) / 11
                let sweepEnd = Angle.degrees(-90 + 360 * fraction)
                context.stroke(
                    Path { $0.addArc(center: ringCenter, radius: radius, startAngle: .degrees(-90), endAngle: sweepEnd, clockwise: false) },
                    with: .color(Color.accentColor),
                    style: StrokeStyle(lineWidth: 3 * s, lineCap: .round)
                )

                // Button dots.
                let dotsTop = y + (Self.cellH + 5 + Self.ringSize + 5) * s
                for (row, zone) in Self.dotZones.enumerated() {
                    let dotY = dotsTop + CGFloat(row) * (Self.dot + Self.dotSpacing) * s
                    let rect = CGRect(x: centerX - Self.dot * s / 2, y: dotY, width: Self.dot * s, height: Self.dot * s)
                    context.fill(Path(ellipseIn: rect), with: .color(dotColor(for: frame[buttonNote: zone.notes[strip]])))
                }
            }

            y += (Self.cellH + 5 + Self.ringSize + 5 + Self.dot * 4 + Self.dotSpacing * 3 + Self.sectionGap) * s

            // Right-hand cluster: label + one dot per button in note order (a density
            // readout, not a physical layout map — see the Round 6 notes).
            context.draw(
                Text("OTHER BUTTONS")
                    .font(.system(size: 6 * s, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.45)),
                at: CGPoint(x: Self.pad * s, y: y + 3 * s),
                anchor: .leading
            )
            y += 10 * s

            for (position, index) in XTouchSurfaceProtocol.rightSectionButtonIndices.enumerated() {
                let row = position / Self.dotColumns
                let column = position % Self.dotColumns
                let rect = CGRect(
                    x: (Self.pad + CGFloat(column) * (Self.dot + Self.dotSpacing)) * s,
                    y: y + CGFloat(row) * (Self.dot + Self.dotSpacing) * s,
                    width: Self.dot * s,
                    height: Self.dot * s
                )
                context.fill(Path(ellipseIn: rect), with: .color(dotColor(for: frame.buttons[index])))
            }
        }
        .frame(width: canvasWidth, height: canvasHeight)
        .background(Theme.previewWell)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline))
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
