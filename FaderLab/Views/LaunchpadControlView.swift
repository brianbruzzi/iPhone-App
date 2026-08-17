import SwiftUI

struct LaunchpadControlView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pixel Art (Launchpad X)").font(.headline)
                Spacer()
                Button {
                    appState.resetPadSettings()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            PixelGridPreviewView(grid: appState.latestPadGrid)
                .frame(width: 220, height: 220)

            Picker("Pattern", selection: $appState.padPatternID) {
                ForEach(PatternOptions.pads) { option in
                    Text(option.displayName).tag(option.id)
                }
            }

            LabeledSlider(label: "Speed", value: $appState.padSpeed, range: 0.1...4, defaultValue: AppState.defaultPadSpeed)
            LabeledSlider(label: "Hue Shift", value: $appState.padHueShift, range: 0...1, defaultValue: AppState.defaultPadHueShift)
            LabeledSlider(label: "Brightness", value: $appState.padBrightness, range: 0...1, defaultValue: AppState.defaultPadBrightness)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    LaunchpadControlView().environment(AppState())
}
