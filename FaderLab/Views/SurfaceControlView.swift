import SwiftUI

struct SurfaceControlView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        PreviewCard(title: "Light Show (X-Touch Surface)", onReset: { appState.resetSurfaceSettings() }) {
            SurfacePreviewView(frame: appState.latestSurfaceFrame)

            Picker("Pattern", selection: $appState.surfacePatternID) {
                ForEach(PatternOptions.surface) { option in
                    Text(option.displayName).tag(option.id)
                }
            }

            LabeledSlider(label: "Speed", value: $appState.surfaceSpeed, range: 0.1...4, defaultValue: AppState.defaultSurfaceSpeed)
            LabeledSlider(label: "Intensity", value: $appState.surfaceIntensity, range: 0...1, defaultValue: AppState.defaultSurfaceIntensity)
        }
    }
}

#Preview {
    SurfaceControlView().environment(AppState())
}
