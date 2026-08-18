import SwiftUI

/// The fixed, non-scrolling strip at the top of the window: the big show pause/play
/// control, the audio transport cluster, the beat-sync toggle, and Reset Everything. Stays
/// visible regardless of how far the pattern cards below have scrolled.
struct TransportBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
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
                    Text("Faders, pixel art, and the X-Touch surface freeze together.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                MasterSyncToggle()

                Button {
                    appState.resetAll()
                } label: {
                    Label("Reset Everything", systemImage: "arrow.counterclockwise")
                }
            }

            Divider()

            LabeledSlider(
                label: "X-Touch Speed (faders + all lights)",
                value: $appState.xTouchSpeed,
                range: 0.1...4,
                defaultValue: AppState.defaultXTouchSpeed
            )

            Divider()

            AudioControlView()
        }
        .padding(16)
        .background(.bar)
    }
}

#Preview {
    TransportBarView().environment(AppState())
}
