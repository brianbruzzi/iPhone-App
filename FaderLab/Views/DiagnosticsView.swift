import SwiftUI
import CoreMIDI
import FaderLabCore

/// The "stop guessing" panel: shows every MIDI port macOS can see, what the surface is
/// actually saying, and buttons that send one known-good message at a time. When faders
/// aren't moving, this is what turns "nothing works" into a specific answer.
struct DiagnosticsView: View {
    @Environment(AppState.self) private var appState
    @State private var isExpanded = false
    @State private var testLEDOn = false

    private var midi: MIDIManager { appState.midiManager }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 16) {
                detectedModeSection
                Divider()
                testSection
                Divider()
                portListSection
                Divider()
                logSection
            }
            .padding(.top, 12)
        } label: {
            HStack {
                Image(systemName: "stethoscope")
                Text("Diagnostics").font(.headline)
                if let error = midi.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Detected mode

    private var detectedModeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Surface mode").font(.subheadline).bold()

            HStack(spacing: 6) {
                if let detected = midi.monitor.detectedMode {
                    Circle()
                        .fill(detected.isSupported ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text("Detected: **\(detected.displayName)**")
                } else {
                    Circle().fill(Color.secondary).frame(width: 8, height: 8)
                    Text("Not detected yet — **touch a fader on the X-Touch** to identify it.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)

            if let detected = midi.monitor.detectedMode, !detected.isSupported {
                Text("""
                     HUI mode can't be driven by this app. Power the X-Touch off, hold \
                     channel 1 SELECT, switch it back on, set encoder 1 to MC and encoder 2 \
                     to USB, then press channel 1 SELECT to save.
                     """)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Send as:").font(.caption)
                Picker("", selection: Binding(
                    get: { midi.surfaceMode },
                    set: { midi.surfaceMode = $0 }
                )) {
                    ForEach(MIDIManager.SurfaceModeSetting.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)

                Button("Forget detection") { midi.monitor.resetDetectedMode() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
    }

    // MARK: - Test buttons

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Send a test message").font(.subheadline).bold()
            Text("If one of these makes the hardware react, that tells us the mode and the port are right.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(testLEDOn ? "Turn SELECT 1 off" : "Light SELECT 1") {
                    testLEDOn.toggle()
                    midi.sendXTouchTestButtonLED(note: 24, on: testLEDOn)
                }
                Button("Fader 1 → middle (MC)") {
                    midi.sendXTouchTestFader(fader: 0, unitValue: 0.5, mode: .mackieControl)
                }
                Button("Fader 1 → middle (Ctrl)") {
                    midi.sendXTouchTestFader(fader: 0, unitValue: 0.5, mode: .ctrl)
                }
            }
            .disabled(!midi.xTouchPortsFound)

            HStack(spacing: 8) {
                Button("Reset X-Touch (lights off, faders down)") {
                    testLEDOn = false
                    midi.sendXTouchResetSurface()
                }
                .disabled(!midi.xTouchPortsFound)
                Button("Launchpad: all pads off") { midi.sendLaunchpadClearAll() }
                    .disabled(!midi.launchpadPortsFound)
                Button("Launchpad: re-enter Programmer mode") { midi.sendLaunchpadProgrammerMode(true) }
                    .disabled(!midi.launchpadPortsFound)
            }

            if !midi.xTouchPortsFound {
                Text("No X-Touch port selected — pick one under Devices above.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Port list

    private var portListSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("MIDI ports macOS can see").font(.subheadline).bold()
                Spacer()
                Button("Refresh") { midi.discoverDevices() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }

            HStack(alignment: .top, spacing: 20) {
                endpointColumn(
                    title: "Inputs (\(midi.availableSources.count))",
                    endpoints: midi.availableSources,
                    selectedName: midi.xTouchSourceName
                )
                endpointColumn(
                    title: "Outputs (\(midi.availableDestinations.count))",
                    endpoints: midi.availableDestinations,
                    selectedName: midi.xTouchDestinationName
                )
            }
        }
    }

    private func endpointColumn(title: String, endpoints: [MIDIEndpointInfo], selectedName: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).bold().foregroundStyle(.secondary)
            if endpoints.isEmpty {
                Text("(none)").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(endpoints) { endpoint in
                    HStack(spacing: 4) {
                        Text(endpoint.displayName == selectedName ? "▸" : " ")
                            .font(.caption)
                            .foregroundStyle(.tint)
                        Text(endpoint.summary)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Live log

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Live MIDI").font(.subheadline).bold()
                Spacer()
                Button(midi.monitor.isPaused ? "Resume" : "Pause") {
                    midi.monitor.isPaused.toggle()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                Button("Clear") { midi.monitor.clear() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }

            Text("Outgoing fader traffic is sampled (it runs ~30x/second); incoming is shown in full.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(midi.monitor.entries) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(entry.direction.rawValue)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(entry.direction == .incoming ? Color.green : Color.blue)
                                    .frame(width: 26, alignment: .leading)
                                Text(entry.hex)
                                    .font(.system(.caption2, design: .monospaced))
                                    .frame(width: 130, alignment: .leading)
                                Text(entry.description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                            }
                            .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
                .frame(height: 160)
                .background(Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onChange(of: midi.monitor.entries.count) {
                    if let last = midi.monitor.entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            if midi.monitor.entries.isEmpty {
                Text("Nothing yet. Touch or move a fader on the X-Touch — anything it sends shows up here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    DiagnosticsView().environment(AppState())
}
