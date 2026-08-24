import SwiftUI
import FaderLabCore

/// Column C: the Launchpad X pixel art — a large square live grid with the pattern
/// controls beneath it. Separate physical device, so it keeps its own card and speed.
struct LaunchpadColumnView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        PreviewCard(title: "Launchpad", onReset: { appState.resetPadSettings() }) {
            HStack {
                Spacer(minLength: 0)
                PixelGridPreviewView(grid: appState.latestPadGrid)
                    // The cap is load-bearing: uncapped, the width-driven grid fills the
                    // whole column and blows the no-scroll height budget.
                    .frame(maxWidth: 420)
                    .aspectRatio(1, contentMode: .fit)
                Spacer(minLength: 0)
            }

            Picker("Pattern", selection: $appState.padPatternID) {
                ForEach(PatternOptions.pads) { option in
                    Text(option.displayName).tag(option.id)
                }
            }

            LabeledSlider(label: "Speed", value: $appState.padSpeed, range: 0.1...4, defaultValue: AppState.defaultPadSpeed)
            LabeledSlider(label: "Hue Shift", value: $appState.padHueShift, range: 0...1, defaultValue: AppState.defaultPadHueShift)
            LabeledSlider(label: "Brightness", value: $appState.padBrightness, range: 0...1, defaultValue: AppState.defaultPadBrightness)

            Picker("Rotation", selection: $appState.padRotation) {
                ForEach(GridRotation.allCases, id: \.self) { rotation in
                    Text(rotation.displayName).tag(rotation)
                }
            }
        }
    }
}

#Preview {
    LaunchpadColumnView().environment(AppState())
}
