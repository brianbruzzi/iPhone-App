import SwiftUI

struct FaderControlView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        PreviewCard(title: "Faders (X-Touch)", onReset: { appState.resetFaderSettings() }) {
            FaderBarsPreviewView(values: appState.latestFaderValues)

            Picker("Pattern", selection: $appState.faderPatternID) {
                ForEach(PatternOptions.faders) { option in
                    Text(option.displayName).tag(option.id)
                }
            }

            LabeledSlider(label: "Speed", value: $appState.faderSpeed, range: 0.1...4, defaultValue: AppState.defaultFaderSpeed)
            LabeledSlider(label: "Amplitude", value: $appState.faderAmplitude, range: 0...1, defaultValue: AppState.defaultFaderAmplitude)
            LabeledSlider(label: "Base Level", value: $appState.faderBaseLevel, range: 0...1, defaultValue: AppState.defaultFaderBaseLevel)
        }
    }
}

#Preview {
    FaderControlView().environment(AppState())
}
