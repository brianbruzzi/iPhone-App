import SwiftUI
import FaderLabCore

/// A UI-friendly (id, display name) pair for a pattern, decoupled from the `any
/// FaderPattern`/`any PadPattern` existential so it can drive a SwiftUI `Picker` directly.
struct PatternOption: Identifiable {
    let id: String
    let displayName: String
}

enum PatternOptions {
    static let faders: [PatternOption] = FaderPatterns.all.map {
        PatternOption(id: type(of: $0).id, displayName: type(of: $0).displayName)
    }
    static let pads: [PatternOption] = PadPatterns.all.map {
        PatternOption(id: type(of: $0).id, displayName: type(of: $0).displayName)
    }
    static let surface: [PatternOption] = SurfacePatterns.all.map {
        PatternOption(id: type(of: $0).id, displayName: type(of: $0).displayName)
    }
}

/// UI label for each rotation, phrased as a turn direction rather than just a bare degree
/// count — the direction itself is exact (a standard clockwise image rotation), but which
/// physical Launchpad edge it lands "down" on depends on how the hardware itself has been
/// turned, which is why `LaunchpadControlView` puts the live preview right above this
/// picker: whichever option visually matches the hardware is the right one.
extension GridRotation {
    var displayName: String {
        switch self {
        case .degrees0: return "None"
        case .degrees90: return "90° Clockwise"
        case .degrees180: return "180°"
        case .degrees270: return "90° Counterclockwise"
        }
    }
}

/// A slider with a label, live numeric readout, a tick mark showing where the default
/// value sits on the track, and a reset button that appears whenever the value has
/// drifted from that default. Shared by the fader/pad control panels.
struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var defaultValue: Double? = nil

    private var isAtDefault: Bool {
        guard let defaultValue else { return true }
        return abs(value - defaultValue) < 0.005
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%.2f", value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let defaultValue, !isAtDefault {
                    Button {
                        value = defaultValue
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .imageScale(.small)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Reset \(label) to default (\(String(format: "%.2f", defaultValue)))")
                }
            }
            Slider(value: $value, in: range)
            if let defaultValue {
                GeometryReader { proxy in
                    let fraction = (defaultValue - range.lowerBound) / (range.upperBound - range.lowerBound)
                    Rectangle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 1.5, height: 5)
                        .offset(x: proxy.size.width * CGFloat(fraction))
                }
                .frame(height: 5)
            }
        }
    }
}
