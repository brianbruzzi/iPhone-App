import SwiftUI

/// Column B: the X-Touch's light show — the merged surface preview (channel strips +
/// right-hand cluster, exactly what the hardware receives) with the two independent
/// pattern selections beneath it.
struct LightsColumnView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        PreviewCard(title: "X-Touch · Lights", onReset: {
            appState.resetSurfaceSettings()
            appState.resetRightSectionSettings()
        }) {
            // One preview for both light sections: `latestSurfaceFrame` is the final
            // merged frame the hardware receives, right-hand splice included.
            HStack {
                Spacer(minLength: 0)
                LiveSurfacePreview(scale: 1.3)
                Spacer(minLength: 0)
            }

            Picker("Channel Strip", selection: $appState.surfacePatternID) {
                ForEach(PatternOptions.surface) { option in
                    Text(option.displayName).tag(option.id)
                }
            }
            LabeledSlider(
                label: "Channel Strip Intensity", value: $appState.surfaceIntensity,
                range: 0...1, defaultValue: AppState.defaultSurfaceIntensity
            )
            Toggle("Reverse SELECT/MUTE/SOLO/REC meter", isOn: $appState.surfaceReversed)
                .toggleStyle(.switch)
                .font(.caption)

            Picker("Other Buttons", selection: $appState.rightSectionPatternID) {
                ForEach(PatternOptions.surface) { option in
                    Text(option.displayName).tag(option.id)
                }
            }
            LabeledSlider(
                label: "Other Buttons Intensity", value: $appState.rightSectionIntensity,
                range: 0...1, defaultValue: AppState.defaultRightSectionIntensity
            )
        }
    }
}

#Preview {
    LightsColumnView().environment(AppState())
}
