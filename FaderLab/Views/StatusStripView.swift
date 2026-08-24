import SwiftUI

/// The slim always-visible strip along the bottom: connection state for both devices, any
/// current error, and the button that opens the Setup & Diagnostics inspector. Replaces
/// the two big disclosure panels that used to live (and force scrolling) under the cards.
struct StatusStripView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        let midi = appState.midiManager
        HStack(spacing: 18) {
            deviceDot("X-Touch", found: midi.xTouchPortsFound, port: midi.xTouchDestinationName)
            deviceDot("Launchpad X", found: midi.launchpadPortsFound, port: midi.launchpadDestinationName)

            if let error = appState.midiStartError ?? midi.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                appState.showDiagnostics.toggle()
            } label: {
                Label("Setup & Diagnostics", systemImage: "stethoscope")
            }
            .buttonStyle(.borderless)
            .help("Open device setup and MIDI diagnostics (⌘⇧D)")
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Theme.raisedBar)
        .overlay(alignment: .top) { Theme.hairline.frame(height: 1) }
    }

    private func deviceDot(_ name: String, found: Bool, port: String?) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(found ? Color.green : Color.red)
                .frame(width: 7, height: 7)
                .shadow(color: (found ? Color.green : Color.red).opacity(0.7), radius: 3)
            Text(name)
            if found, let port, !port.isEmpty {
                Text("· \(port)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

#Preview {
    StatusStripView().environment(AppState())
}
