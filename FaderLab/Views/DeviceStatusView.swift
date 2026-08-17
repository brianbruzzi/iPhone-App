import SwiftUI

struct DeviceStatusView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Devices").font(.headline)

            statusRow(name: "Behringer X-Touch", connected: appState.midiManager.xTouchConnected)
            statusRow(name: "Novation Launchpad X", connected: appState.midiManager.launchpadConnected)

            Text("Neither device is required — the previews below the pattern pickers show exactly what would be sent, even with nothing plugged in.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error = appState.midiStartError {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            if !appState.midiManager.xTouchConnected || !appState.midiManager.launchpadConnected {
                manualPicker
            }
        }
    }

    private func statusRow(name: String, connected: Bool) -> some View {
        HStack {
            Circle()
                .fill(connected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(name)
            Spacer()
            Text(connected ? "Connected" : "Not Found")
                .foregroundStyle(.secondary)
        }
    }

    private var manualPicker: some View {
        DisclosureGroup("Manually select MIDI ports") {
            VStack(alignment: .leading, spacing: 10) {
                manualDeviceRow(
                    label: "X-Touch",
                    onSelectSource: { appState.midiManager.useManualXTouch(sourceName: $0, destinationName: nil) },
                    onSelectDestination: { appState.midiManager.useManualXTouch(sourceName: nil, destinationName: $0) }
                )
                manualDeviceRow(
                    label: "Launchpad X — choose the \"MIDI\" port, not \"DAW\"",
                    onSelectSource: { appState.midiManager.useManualLaunchpad(sourceName: $0, destinationName: nil) },
                    onSelectDestination: { appState.midiManager.useManualLaunchpad(sourceName: nil, destinationName: $0) }
                )
            }
            .padding(.top, 4)
        }
        .font(.caption)
    }

    private func manualDeviceRow(
        label: String,
        onSelectSource: @escaping (String) -> Void,
        onSelectDestination: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).bold()
            HStack {
                actionPicker(title: "Input", options: appState.midiManager.availableSourceNames, onSelect: onSelectSource)
                actionPicker(title: "Output", options: appState.midiManager.availableDestinationNames, onSelect: onSelectDestination)
            }
        }
    }

    /// A "menu of actions" picker: choosing an option fires `onSelect` immediately rather
    /// than maintaining its own persisted selection (the real state lives in `MIDIManager`).
    private func actionPicker(title: String, options: [String], onSelect: @escaping (String) -> Void) -> some View {
        Picker(title, selection: Binding<String>(get: { "" }, set: onSelect)) {
            Text("Select…").tag("")
            ForEach(options, id: \.self) { name in
                Text(name).tag(name)
            }
        }
    }
}

#Preview {
    DeviceStatusView().environment(AppState())
}
