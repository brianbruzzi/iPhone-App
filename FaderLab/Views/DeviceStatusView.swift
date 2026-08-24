import SwiftUI
import CoreMIDI

struct DeviceStatusView: View {
    @Environment(AppState.self) private var appState
    @State private var isExpanded: Bool

    /// `initiallyExpanded` seeds the disclosure state on first appearance — the inspector
    /// opens this expanded so it shows content, not a collapsed chevron.
    init(initiallyExpanded: Bool = false) {
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    private var midi: MIDIManager { appState.midiManager }

    private var allPortsFound: Bool {
        midi.xTouchPortsFound && midi.launchpadPortsFound
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
                .padding(.top, 8)
        } label: {
            HStack {
                Image(systemName: "cable.connector")
                Text("Setup & Devices").font(.headline)
                Circle()
                    .fill(allPortsFound ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                if let error = appState.midiStartError ?? midi.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRow(
                name: "Behringer X-Touch",
                found: midi.xTouchPortsFound,
                portName: midi.xTouchDestinationName
            )
            statusRow(
                name: "Novation Launchpad X",
                found: midi.launchpadPortsFound,
                portName: midi.launchpadDestinationName
            )

            Text("Neither device is required — the previews below show exactly what would be sent, even with nothing plugged in.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = appState.midiStartError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let error = midi.lastError {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Dismiss") { midi.clearError() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }

            xTouchSetupHint
            manualPicker
        }
    }

    // MARK: - Status rows

    private func statusRow(name: String, found: Bool, portName: String?) -> some View {
        HStack {
            Circle()
                .fill(found ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(name)
            if found, let portName, !portName.isEmpty {
                Text("· \(portName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(found ? "Port found" : "Not found")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - X-Touch mode setup

    @ViewBuilder
    private var xTouchSetupHint: some View {
        // The X-Touch ships in HUI mode, where it ignores everything this app sends. That
        // makes "port found but nothing moves" the single most likely failure, so the fix
        // is spelled out rather than buried in the README.
        DisclosureGroup("X-Touch not moving? It probably needs MC mode (one-time setup)") {
            VStack(alignment: .leading, spacing: 4) {
                Text("The X-Touch ships in **HUI mode**, which ignores the messages this app sends. Switch it once:")
                    .fixedSize(horizontal: false, vertical: true)
                Text("1. Power the X-Touch **off**")
                Text("2. Hold the **channel 1 SELECT** button")
                Text("3. Keeping it held, switch the **power on** (hold ~2 seconds)")
                Text("4. Turn **encoder 1** to `MC`, and **encoder 2** to `USB`")
                Text("5. Press **channel 1 SELECT** again to save")
                Text("Then open Diagnostics below and touch a fader to confirm it's talking MC.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
    }

    // MARK: - Manual port selection

    /// Always available — it used to be hidden whenever both devices reported "found,"
    /// which is exactly the situation where a wrong-but-matching port needs overriding.
    private var manualPicker: some View {
        DisclosureGroup("Choose MIDI ports manually") {
            VStack(alignment: .leading, spacing: 10) {
                deviceRow(
                    label: "X-Touch",
                    note: "If you see more than one X-Touch port, avoid any labelled EXT — that one goes out the rear DIN socket.",
                    selectedSource: midi.xTouchSourceName,
                    selectedDestination: midi.xTouchDestinationName,
                    onSelectSource: { midi.useManualXTouchSource($0) },
                    onSelectDestination: { midi.useManualXTouchDestination($0) }
                )
                deviceRow(
                    label: "Launchpad X",
                    note: "Choose the \"LPX MIDI\" pair, not \"LPX DAW\".",
                    selectedSource: midi.launchpadSourceName,
                    selectedDestination: midi.launchpadDestinationName,
                    onSelectSource: { midi.useManualLaunchpadSource($0) },
                    onSelectDestination: { midi.useManualLaunchpadDestination($0) }
                )

                if midi.hasManualSelection {
                    Button("Go back to automatic detection") {
                        midi.resetToAutomaticSelection()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .padding(.top, 6)
        }
        .font(.caption)
    }

    private func deviceRow(
        label: String,
        note: String,
        selectedSource: String?,
        selectedDestination: String?,
        onSelectSource: @escaping (MIDIEndpointRef) -> Void,
        onSelectDestination: @escaping (MIDIEndpointRef) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).bold()
            Text(note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                endpointMenu(
                    title: "Input",
                    endpoints: midi.availableSources,
                    selectedName: selectedSource,
                    onSelect: onSelectSource
                )
                endpointMenu(
                    title: "Output",
                    endpoints: midi.availableDestinations,
                    selectedName: selectedDestination,
                    onSelect: onSelectDestination
                )
            }
        }
    }

    /// A Menu of buttons rather than a Picker: selection lives in MIDIManager, and a Picker
    /// bound to a constant getter needs unique tags — which empty-named ports don't have,
    /// causing them to silently no-op.
    private func endpointMenu(
        title: String,
        endpoints: [MIDIEndpointInfo],
        selectedName: String?,
        onSelect: @escaping (MIDIEndpointRef) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(.secondary)
            Menu {
                if endpoints.isEmpty {
                    Text("No ports found")
                } else {
                    ForEach(endpoints) { endpoint in
                        Button {
                            onSelect(endpoint.endpointRef)
                        } label: {
                            Text(endpoint.displayName.isEmpty ? "(unnamed port)" : endpoint.summary)
                        }
                    }
                }
            } label: {
                Text(selectedName.flatMap { $0.isEmpty ? nil : $0 } ?? "Select…")
                    .lineLimit(1)
            }
            .frame(maxWidth: 220)
        }
    }
}

#Preview {
    DeviceStatusView().environment(AppState())
}
