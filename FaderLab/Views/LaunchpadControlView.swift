import SwiftUI

struct LaunchpadControlView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        VStack(alignment: .leading, spacing: 10) {
            Text("Pixel Art (Launchpad X)").font(.headline)

            PixelGridPreviewView(grid: appState.latestPadGrid)
                .frame(width: 220, height: 220)

            Picker("Pattern", selection: $appState.padPatternID) {
                ForEach(PatternOptions.pads) { option in
                    Text(option.displayName).tag(option.id)
                }
            }

            LabeledSlider(label: "Speed", value: $appState.padSpeed, range: 0.1...4)
            LabeledSlider(label: "Hue Shift", value: $appState.padHueShift, range: 0...1)
            LabeledSlider(label: "Brightness", value: $appState.padBrightness, range: 0...1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    LaunchpadControlView().environment(AppState())
}
