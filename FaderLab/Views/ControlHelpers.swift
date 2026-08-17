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
}

/// A slider with a label and live numeric readout, shared by the fader/pad control panels.
struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%.2f", value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range)
        }
    }
}
