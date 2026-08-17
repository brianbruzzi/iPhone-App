import SwiftUI

struct FaderControlView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        VStack(alignment: .leading, spacing: 10) {
            Text("Faders (X-Touch)").font(.headline)

            FaderBarsPreviewView(values: appState.latestFaderValues)

            Picker("Pattern", selection: $appState.faderPatternID) {
                ForEach(PatternOptions.faders) { option in
                    Text(option.displayName).tag(option.id)
                }
            }

            LabeledSlider(label: "Speed", value: $appState.faderSpeed, range: 0.1...4)
            LabeledSlider(label: "Amplitude", value: $appState.faderAmplitude, range: 0...1)
            LabeledSlider(label: "Base Level", value: $appState.faderBaseLevel, range: 0...1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    FaderControlView().environment(AppState())
}
