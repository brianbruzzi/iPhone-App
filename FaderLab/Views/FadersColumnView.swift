import SwiftUI

/// Column A: the X-Touch's motorized faders — big live preview plus motion controls —
/// and, below a divider, the meters & display controls (VU meters default to following
/// the faders, so they live with them). The card's Reset covers exactly this card.
struct FadersColumnView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        PreviewCard(title: "X-Touch · Faders", onReset: {
            appState.resetFaderSettings()
            appState.vuMeterSource = AppState.defaultVUMeterSource
            appState.displayText = AppState.defaultDisplayText
        }) {
            LiveFaderBars(barHeight: 280)

            Picker("Motion", selection: $appState.faderPatternID) {
                ForEach(PatternOptions.faders) { option in
                    Text(option.displayName).tag(option.id)
                }
            }
            LabeledSlider(
                label: "Amplitude", value: $appState.faderAmplitude,
                range: 0...1, defaultValue: AppState.defaultFaderAmplitude
            )
            LabeledSlider(
                label: "Base Level", value: $appState.faderBaseLevel,
                range: 0...1, defaultValue: AppState.defaultFaderBaseLevel
            )

            Divider().padding(.vertical, 4)

            SectionHeader("Meters & Display")

            Picker("VU Meters", selection: $appState.vuMeterSource) {
                ForEach(VUMeterSource.allCases) { source in
                    Text(source.displayName).tag(source)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Display Text").font(.caption)
                TextField("FADER LAB", text: $appState.displayText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                Text("12 characters on the 7-segment display. M, W, K, V and X only render roughly.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    FadersColumnView().environment(AppState())
}
