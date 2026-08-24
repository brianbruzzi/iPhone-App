import SwiftUI

/// The whole stage on one screen, designed for a 1920x1080 frame with zero scrolling:
/// transport bar on top, three equal columns (faders / X-Touch lights / Launchpad), a
/// slim device-status strip along the bottom, and Setup & Diagnostics in a non-modal
/// inspector so the live previews stay visible while debugging MIDI.
struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        VStack(spacing: 0) {
            TransportBarView()

            HStack(alignment: .top, spacing: 16) {
                column { FadersColumnView() }
                column { LightsColumnView() }
                column { LaunchpadColumnView() }
            }
            .padding(16)
            .frame(maxHeight: .infinity, alignment: .top)

            StatusStripView()
        }
        .background(Theme.stage.ignoresSafeArea())
        .frame(minWidth: 1360, minHeight: 900)
        .inspector(isPresented: $appState.showDiagnostics) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DeviceStatusView(initiallyExpanded: true)
                    DiagnosticsView(initiallyExpanded: true)
                }
                .padding(16)
            }
            .inspectorColumnWidth(min: 360, ideal: 440, max: 560)
        }
    }

    private func column<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) {
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ContentView().environment(AppState())
}
