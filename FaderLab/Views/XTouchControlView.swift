import SwiftUI

/// Everything the X-Touch does, in one card: motorized fader motion, the channel-strip
/// light show (the button rows above the faders, plus the encoder rings and scribble
/// strips), and the right-hand control cluster — which can follow the fader show or run a
/// pattern of its own. Speed for all three lives on the single X-Touch Speed slider in the
/// transport bar; there are no per-section speed sliders. The Launchpad X is a separate
/// physical device and keeps its own card.
struct XTouchControlView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        PreviewCard(title: "X-Touch", onReset: { appState.resetXTouchSettings() }) {
            sectionHeader("Faders")
            FaderBarsPreviewView(values: appState.latestFaderValues)

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

            sectionHeader("Lights")
            // One preview for both light sections: `latestSurfaceFrame` is the final merged
            // frame the hardware receives, right-hand splice included.
            SurfacePreviewView(frame: appState.latestSurfaceFrame)

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

            Divider().padding(.vertical, 4)

            sectionHeader("Meters & Display")

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

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }
}

#Preview {
    XTouchControlView().environment(AppState())
}
