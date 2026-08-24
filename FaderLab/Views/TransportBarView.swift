import SwiftUI

/// The fixed strip at the top of the window, one row of three clusters: the show
/// transport (pause/resume + reset), the audio transport (file, playback, position,
/// tempo), and the sync cluster (beat-sync toggle + the single X-Touch speed control).
struct TransportBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        HStack(spacing: 16) {
            // Show cluster
            HStack(spacing: 12) {
                Button {
                    appState.togglePatternPause()
                } label: {
                    Image(systemName: appState.isPatternPaused ? "play.fill" : "pause.fill")
                        .font(.title2)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderedProminent)
                .help(appState.isPatternPaused ? "Resume the show" : "Pause the show")

                VStack(alignment: .leading, spacing: 1) {
                    Text(appState.isPatternPaused ? "Paused" : "Running").font(.headline)
                    Text("Faders, lights, and pixels freeze together.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    appState.resetAll()
                } label: {
                    Label("Reset Everything", systemImage: "arrow.counterclockwise")
                }
            }

            clusterDivider

            AudioControlView()
                .frame(maxWidth: .infinity, alignment: .leading)

            clusterDivider

            // Sync cluster
            HStack(spacing: 14) {
                MasterSyncToggle()
                LabeledSlider(
                    label: "X-Touch Speed",
                    value: $appState.xTouchSpeed,
                    range: 0.1...4,
                    defaultValue: AppState.defaultXTouchSpeed
                )
                .frame(width: 280)
                .help("One speed for everything on the X-Touch: fader motion and all lights.")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.raisedBar)
        .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
    }

    private var clusterDivider: some View {
        Theme.hairline.frame(width: 1, height: 44)
    }
}

#Preview {
    TransportBarView().environment(AppState())
}
