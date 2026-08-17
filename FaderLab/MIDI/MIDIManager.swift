import CoreMIDI
import Observation
import FaderLabCore

enum MIDIManagerError: Error, CustomStringConvertible {
    case clientCreationFailed(OSStatus)
    case portCreationFailed(OSStatus)

    var description: String {
        switch self {
        case .clientCreationFailed(let status): return "Couldn't create MIDI client (error \(status))"
        case .portCreationFailed(let status): return "Couldn't create MIDI port (error \(status))"
        }
    }
}

/// A discovered CoreMIDI endpoint, with the exact name macOS reports. Surfaced in the
/// diagnostics panel — device naming varies by model and firmware, so showing the real
/// strings beats guessing at them.
struct MIDIEndpointInfo: Identifiable, Equatable {
    let id: MIDIUniqueID
    let endpointRef: MIDIEndpointRef
    let displayName: String
    let manufacturer: String
    let model: String

    var summary: String {
        var parts = [displayName.isEmpty ? "(unnamed)" : displayName]
        if !manufacturer.isEmpty { parts.append(manufacturer) }
        if !model.isEmpty, model != displayName { parts.append(model) }
        return parts.joined(separator: " · ")
    }
}

/// Owns all CoreMIDI I/O: discovers the X-Touch and Launchpad X, sends fader/lighting
/// frames, and decodes incoming surface messages. The only file in the app importing
/// CoreMIDI; everything else works with plain values.
@Observable
final class MIDIManager {
    /// True when endpoints matching the device name were found. Deliberately *not* called
    /// "connected" — a name match proves nothing about whether bytes actually arrive, and
    /// conflating the two is what made an earlier bug so hard to see.
    private(set) var xTouchPortsFound = false
    private(set) var launchpadPortsFound = false

    private(set) var xTouchSourceName: String?
    private(set) var xTouchDestinationName: String?
    private(set) var launchpadSourceName: String?
    private(set) var launchpadDestinationName: String?

    private(set) var availableSources: [MIDIEndpointInfo] = []
    private(set) var availableDestinations: [MIDIEndpointInfo] = []

    /// Last error from a send or connect attempt, surfaced in the UI. Without this the app
    /// cannot report that MIDI output failed at all.
    private(set) var lastError: String?

    /// Which protocol to speak to the X-Touch. `.auto` follows whatever the surface's own
    /// messages reveal, falling back to Mackie Control until something conclusive arrives.
    var surfaceMode: SurfaceModeSetting = .auto

    let monitor = MIDIMonitor()

    var onXTouchFaderTouch: ((_ faderIndex: Int, _ touched: Bool) -> Void)?
    var onXTouchFaderPositionReport: ((_ faderIndex: Int, _ unitValue: Double) -> Void)?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()
    private var isStarted = false

    private var xTouchSource: MIDIEndpointRef?
    private var xTouchDestination: MIDIEndpointRef?
    private var launchpadSource: MIDIEndpointRef?
    private var launchpadDestination: MIDIEndpointRef?

    /// Set once the user picks an endpoint by hand, so automatic re-discovery (which fires
    /// on every CoreMIDI setup change) can't silently revert their choice.
    private var xTouchSourceIsManual = false
    private var xTouchDestinationIsManual = false
    private var launchpadSourceIsManual = false
    private var launchpadDestinationIsManual = false

    private var connectedSources: Set<MIDIEndpointRef> = []
    private var wasLaunchpadDestinationPresent = false

    /// Dedupes outgoing Launchpad frames. Lives here rather than in the caller so every
    /// path that touches the Launchpad (pattern frames, the diagnostics "all pads off" and
    /// "re-enter Programmer mode" buttons) shares one true record of what's on the
    /// hardware — a cache that only the pattern path updated could go stale the moment
    /// anything else changed the pads out from under it.
    private var lastSentPadGrid: PixelGrid?

    enum SurfaceModeSetting: String, CaseIterable, Identifiable {
        case auto
        case mackieControl
        case ctrl

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .auto: return "Auto-detect"
            case .mackieControl: return "MC (Mackie Control)"
            case .ctrl: return "Ctrl (standard MIDI)"
            }
        }
    }

    /// The protocol actually used for output right now, resolving `.auto` against whatever
    /// the surface has revealed about itself.
    var effectiveSurfaceMode: SurfaceMode {
        switch surfaceMode {
        case .mackieControl: return .mackieControl
        case .ctrl: return .ctrl
        case .auto:
            // HUI can't be driven by this app, so there's nothing useful to switch to —
            // keep sending MC and let the UI tell the user to change the hardware mode.
            guard let detected = monitor.detectedMode, detected.isSupported else {
                return .mackieControl
            }
            return detected
        }
    }

    // MARK: - Lifecycle

    func start() throws {
        guard !isStarted else { return }

        var newClient = MIDIClientRef()
        let clientStatus = MIDIClientCreateWithBlock("FaderLab" as CFString, &newClient) { [weak self] notification in
            // Only full setup changes matter; property-change notifications fire constantly
            // as other apps open and close ports, and re-running discovery on each one
            // used to stomp manual endpoint selections.
            guard notification.pointee.messageID == .msgSetupChanged else { return }
            DispatchQueue.main.async { self?.discoverDevices() }
        }
        guard clientStatus == noErr else { throw MIDIManagerError.clientCreationFailed(clientStatus) }
        client = newClient

        var newInputPort = MIDIPortRef()
        let inputStatus = MIDIInputPortCreateWithBlock(client, "FaderLab Input" as CFString, &newInputPort) { [weak self] packetList, _ in
            self?.handleIncoming(packetList)
        }
        guard inputStatus == noErr else { throw MIDIManagerError.portCreationFailed(inputStatus) }
        inputPort = newInputPort

        var newOutputPort = MIDIPortRef()
        let outputStatus = MIDIOutputPortCreate(client, "FaderLab Output" as CFString, &newOutputPort)
        guard outputStatus == noErr else { throw MIDIManagerError.portCreationFailed(outputStatus) }
        outputPort = newOutputPort

        isStarted = true
        discoverDevices()
    }

    /// Leaves the Launchpad in a clean state and tears down CoreMIDI. Best effort — SwiftUI
    /// doesn't guarantee this runs on every quit path.
    func stop() {
        if launchpadDestination != nil {
            send(LaunchpadXProtocol.clearAllMessage(), to: launchpadDestination)
            send(LaunchpadXProtocol.programmerModeMessage(enabled: false), to: launchpadDestination)
        }

        if client != 0 {
            MIDIClientDispose(client)
        }

        // Zero everything: MIDIClientDispose invalidates the ports, and leaving stale
        // non-zero refs behind would let send() sail past its guard into a dead port.
        client = MIDIClientRef()
        inputPort = MIDIPortRef()
        outputPort = MIDIPortRef()
        xTouchSource = nil
        xTouchDestination = nil
        launchpadSource = nil
        launchpadDestination = nil
        connectedSources.removeAll()
        xTouchPortsFound = false
        launchpadPortsFound = false
        wasLaunchpadDestinationPresent = false
        lastSentPadGrid = nil
        isStarted = false
    }

    // MARK: - Outbound

    /// Sends all 9 fader positions in a single packet list. `values` are 0...1, with `.nan`
    /// meaning "skip this fader" (user is touching it, or automation is off).
    func sendXTouchFaderFrame(_ values: [Double]) {
        guard let destination = xTouchDestination, outputPort != 0 else { return }

        var messages: [[UInt8]] = []
        messages.reserveCapacity(values.count)
        for (index, value) in values.enumerated() where !value.isNaN {
            switch effectiveSurfaceMode {
            case .mackieControl:
                messages.append(XTouchProtocol.pitchBendBytes(fader: index, unitValue: value))
            case .ctrl:
                messages.append(XTouchCtrlProtocol.faderBytes(fader: index, unitValue: value))
            case .hui:
                return // Not drivable; the UI prompts the user to switch the hardware mode.
            }
        }
        guard !messages.isEmpty else { return }

        if let first = messages.first {
            monitor.recordOutgoing(first)
        }
        sendBatch(messages, to: destination)
    }

    /// Sends a single fader position — used by the diagnostics test buttons.
    func sendXTouchTestFader(fader: Int, unitValue: Double, mode: SurfaceMode) {
        let bytes: [UInt8]
        switch mode {
        case .mackieControl: bytes = XTouchProtocol.pitchBendBytes(fader: fader, unitValue: unitValue)
        case .ctrl: bytes = XTouchCtrlProtocol.faderBytes(fader: fader, unitValue: unitValue)
        case .hui: return
        }
        monitor.recordOutgoing(bytes, force: true)
        send(bytes, to: xTouchDestination)
    }

    /// Lights (or clears) a Mackie Control button LED — used by the diagnostics test buttons.
    func sendXTouchTestButtonLED(note: UInt8, on: Bool) {
        let bytes: [UInt8] = [0x90, note, on ? 0x7F : 0x00]
        monitor.recordOutgoing(bytes, force: true)
        send(bytes, to: xTouchDestination)
    }

    /// Turns off every Mackie Control button LED (notes 0...118) and drops all faders to
    /// zero — i.e. puts the surface back to a blank state after testing.
    func sendXTouchResetSurface(includeFaders: Bool = true) {
        guard let destination = xTouchDestination else { return }
        monitor.recordOutgoing([0x90, 0x00, 0x00], force: true)

        // Chunked: 119 three-byte messages coalesce well past a single packet's 256-byte
        // data capacity, so hand CoreMIDI a manageable list at a time.
        let ledMessages = (UInt8(0)...UInt8(118)).map { [0x90, $0, 0x00] }
        for chunk in stride(from: 0, to: ledMessages.count, by: 32) {
            let slice = Array(ledMessages[chunk..<min(chunk + 32, ledMessages.count)])
            sendBatch(slice, to: destination)
        }

        if includeFaders {
            let faderMessages = (0..<XTouchProtocol.faderCount).map {
                XTouchProtocol.pitchBendBytes(fader: $0, unitValue: 0)
            }
            sendBatch(faderMessages, to: destination)
        }
    }

    func sendLaunchpadFrame(_ grid: PixelGrid) {
        guard grid != lastSentPadGrid else { return }
        lastSentPadGrid = grid
        let bytes = LaunchpadXProtocol.frameMessage(grid)
        monitor.recordOutgoing(bytes)
        send(bytes, to: launchpadDestination)
    }

    func sendLaunchpadProgrammerMode(_ enabled: Bool) {
        // Entering/leaving Programmer mode can change what's actually lit without going
        // through sendLaunchpadFrame, so the cache can no longer vouch for the hardware.
        lastSentPadGrid = nil
        let bytes = LaunchpadXProtocol.programmerModeMessage(enabled: enabled)
        monitor.recordOutgoing(bytes, force: true)
        send(bytes, to: launchpadDestination)
    }

    func sendLaunchpadClearAll() {
        lastSentPadGrid = .allBlack
        let bytes = LaunchpadXProtocol.clearAllMessage()
        monitor.recordOutgoing(bytes, force: true)
        send(bytes, to: launchpadDestination)
    }

    func clearError() {
        lastError = nil
    }

    // MARK: - Raw send

    private func send(_ bytes: [UInt8], to destination: MIDIEndpointRef?) {
        guard let destination else { return }
        sendBatch([bytes], to: destination)
    }

    /// Packs several short messages into one `MIDIPacketList` and sends it once. The fader
    /// path emits 9 messages every tick at 30Hz; batching turns 270 sends/sec into 30.
    ///
    /// If batching fails for any reason, this falls back to sending each message on its
    /// own rather than dropping the frame — a bad batch should degrade performance, never
    /// silence the output.
    private func sendBatch(_ messages: [[UInt8]], to destination: MIDIEndpointRef) {
        guard outputPort != 0, !messages.isEmpty else { return }

        // Worst case is every message landing in its own packet: 8-byte timestamp +
        // 2-byte length + payload, rounded up for alignment, plus the list header.
        let perMessage = messages.reduce(0) { $0 + $1.count + 16 }
        let bufferSize = max(1024, perMessage + 256)

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: bufferSize,
            alignment: MemoryLayout<MIDIPacketList>.alignment
        )
        defer { raw.deallocate() }

        let packetList = raw.bindMemory(to: MIDIPacketList.self, capacity: 1)
        var packet = MIDIPacketListInit(packetList)
        var packedAll = true

        for message in messages {
            let next = MIDIPacketListAdd(packetList, bufferSize, packet, 0, message.count, message)
            // MIDIPacketListAdd returns NULL when a message won't fit. The SDK declares the
            // return as non-optional, so test the address rather than nil-checking.
            //
            // Do NOT test whether numPackets grew: messages sharing a timestamp are
            // deliberately coalesced into one packet, so the count stays put on every
            // message after the first. Treating that as failure made every multi-message
            // send (the 9-fader frame, the all-LEDs-off sweep) bail out silently.
            guard UInt(bitPattern: UnsafeRawPointer(next)) != 0 else {
                packedAll = false
                break
            }
            packet = next
        }

        guard packedAll else {
            sendIndividually(messages, to: destination)
            return
        }

        let status = MIDISend(outputPort, destination, packetList)
        if status != noErr {
            reportError("MIDISend failed with error \(status)")
        }
    }

    /// One `MIDISend` per message. Slower, but immune to any packing problem.
    private func sendIndividually(_ messages: [[UInt8]], to destination: MIDIEndpointRef) {
        for message in messages {
            let bufferSize = max(512, message.count + 64)
            let raw = UnsafeMutableRawPointer.allocate(
                byteCount: bufferSize,
                alignment: MemoryLayout<MIDIPacketList>.alignment
            )
            defer { raw.deallocate() }

            let packetList = raw.bindMemory(to: MIDIPacketList.self, capacity: 1)
            let packet = MIDIPacketListInit(packetList)
            let next = MIDIPacketListAdd(packetList, bufferSize, packet, 0, message.count, message)
            guard UInt(bitPattern: UnsafeRawPointer(next)) != 0 else {
                reportError("Couldn't pack a \(message.count)-byte MIDI message")
                continue
            }

            let status = MIDISend(outputPort, destination, packetList)
            if status != noErr {
                reportError("MIDISend failed with error \(status)")
            }
        }
    }

    private func reportError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lastError = message
        }
    }

    // MARK: - Inbound

    private func handleIncoming(_ packetListPointer: UnsafePointer<MIDIPacketList>) {
        // Iterate the real packet list. Copying `.packet` into a local and calling
        // MIDIPacketNext on it walks off the end of a stack copy rather than through the
        // buffer, which is a genuine memory-safety bug for multi-packet lists.
        for packet in packetListPointer.unsafeSequence() {
            // `packet.pointee.length` can legitimately exceed 256 (CoreMIDI docs: the
            // 256-byte `data` field is a convenience size, not a hard cap), and it's driven
            // by the MIDIServer rather than anything this app controls, so bound it before
            // using it as a read length.
            let length = min(Int(packet.pointee.length), 65_536)
            guard length > 0 else { continue }

            // `packet.pointee.data` is a fixed 256-byte tuple; evaluating it copies all 256
            // bytes regardless of `length` — past the end of a short packet, and past the
            // end of the list entirely for the final one. Read exactly `length` bytes from
            // the packet's own storage instead. `?? 10` rather than `!`: this runs on
            // CoreMIDI's realtime callback thread, where a trap is the worst possible
            // failure mode, and 10 (8-byte timestamp + 2-byte length) is correct on every
            // Apple platform even in the fallback case.
            let dataOffset = MemoryLayout<MIDIPacket>.offset(of: \.data) ?? 10
            let base = UnsafeRawPointer(packet).advanced(by: dataOffset)
            let bytes = [UInt8](UnsafeRawBufferPointer(start: base, count: length))

            // A single packet often bundles several simultaneous messages (e.g. two faders
            // that moved at the same timestamp) — treating the whole packet as one message
            // silently dropped everything after the first.
            for message in MIDIMessageDecoder.splitMessages(bytes) {
                handleIncomingMessage(message)
            }
        }
    }

    private func handleIncomingMessage(_ bytes: [UInt8]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.monitor.recordIncoming(bytes)

            // Touch sense: check both protocols, since the surface's mode determines which
            // note range it uses and the two ranges partially overlap.
            if let touch = XTouchProtocol.decodeTouch(bytes) {
                self.onXTouchFaderTouch?(touch.fader, touch.touched)
            } else if let touch = XTouchCtrlProtocol.decodeTouch(bytes) {
                self.onXTouchFaderTouch?(touch.fader, touch.touched)
            } else if let position = XTouchProtocol.decodePitchBend(bytes) {
                self.onXTouchFaderPositionReport?(position.fader, XTouchProtocol.unit(fromValue14: position.value14))
            } else if let position = XTouchCtrlProtocol.decodeFader(bytes) {
                self.onXTouchFaderPositionReport?(position.fader, XTouchCtrlProtocol.unit(fromValue7: position.value7))
            }
        }
    }

    // MARK: - Device discovery

    func refreshEndpointLists() {
        availableSources = (0..<MIDIGetNumberOfSources()).map { endpointInfo(for: MIDIGetSource($0)) }
        availableDestinations = (0..<MIDIGetNumberOfDestinations()).map { endpointInfo(for: MIDIGetDestination($0)) }
    }

    func discoverDevices() {
        refreshEndpointLists()

        let previousXTouchSource = xTouchSource
        let previousLaunchpadSource = launchpadSource

        if !xTouchSourceIsManual {
            xTouchSource = availableSources.first(where: { MIDIManager.looksLikeXTouch($0.displayName) })?.endpointRef
        }
        if !xTouchDestinationIsManual {
            xTouchDestination = availableDestinations.first(where: { MIDIManager.looksLikeXTouch($0.displayName) })?.endpointRef
        }
        if !launchpadSourceIsManual {
            launchpadSource = availableSources.first(where: { MIDIManager.looksLikeLaunchpadMIDIPort($0.displayName) })?.endpointRef
        }
        if !launchpadDestinationIsManual {
            launchpadDestination = availableDestinations.first(where: { MIDIManager.looksLikeLaunchpadMIDIPort($0.displayName) })?.endpointRef
        }

        disconnectSourceIfOrphaned(previousXTouchSource)
        disconnectSourceIfOrphaned(previousLaunchpadSource)
        connectSources()
        refreshStatus()
    }

    private func refreshStatus() {
        xTouchPortsFound = xTouchSource != nil && xTouchDestination != nil
        launchpadPortsFound = launchpadSource != nil && launchpadDestination != nil

        xTouchSourceName = xTouchSource.flatMap { name(matching: $0, in: availableSources) }
        xTouchDestinationName = xTouchDestination.flatMap { name(matching: $0, in: availableDestinations) }
        launchpadSourceName = launchpadSource.flatMap { name(matching: $0, in: availableSources) }
        launchpadDestinationName = launchpadDestination.flatMap { name(matching: $0, in: availableDestinations) }

        // Gated on the *destination* specifically, not "both ports found": Programmer mode
        // only needs somewhere to send the SysEx, and gating it on the input port too meant
        // a Launchpad with a found destination but no matched source never got switched out
        // of Live mode, so nothing it was sent would light correctly.
        let isLaunchpadDestinationPresent = launchpadDestination != nil
        if isLaunchpadDestinationPresent, !wasLaunchpadDestinationPresent {
            sendLaunchpadProgrammerMode(true)
        }
        wasLaunchpadDestinationPresent = isLaunchpadDestinationPresent
    }

    private func name(matching endpoint: MIDIEndpointRef, in list: [MIDIEndpointInfo]) -> String? {
        list.first(where: { $0.endpointRef == endpoint })?.displayName
    }

    private func connectSources() {
        guard inputPort != 0 else { return }
        for source in [xTouchSource, launchpadSource].compactMap({ $0 }) where !connectedSources.contains(source) {
            let status = MIDIPortConnectSource(inputPort, source, nil)
            if status == noErr {
                connectedSources.insert(source)
            } else {
                reportError("Couldn't listen to a MIDI input (error \(status))")
            }
        }
    }

    /// Disconnects `endpoint` if nothing currently uses it. Without this, switching which
    /// port the X-Touch reads from (whether auto-discovery finding a better match, or the
    /// user picking manually) left the *previous* endpoint connected too, so both kept
    /// feeding touch/fader events into the same callbacks.
    private func disconnectSourceIfOrphaned(_ endpoint: MIDIEndpointRef?) {
        guard let endpoint, endpoint != xTouchSource, endpoint != launchpadSource else { return }
        guard connectedSources.contains(endpoint) else { return }
        MIDIPortDisconnectSource(inputPort, endpoint)
        connectedSources.remove(endpoint)
    }

    /// The full-size X-Touch's CoreMIDI name isn't a documented constant, and reports vary
    /// (some units expose an `X-Touch INT` control-surface port). Match the family, then
    /// exclude the models and ports this app can't drive: the Extender, the Compact/Mini/One
    /// (different protocols), and any `EXT` port, which forwards bytes out the rear DIN
    /// socket rather than to the faders.
    static func looksLikeXTouch(_ name: String) -> Bool {
        let lower = name.lowercased().replacingOccurrences(of: " ", with: "")
        guard lower.contains("x-touch") || lower.contains("xtouch") else { return false }
        let excluded = ["ext", "extender", "mini", "compact", "one"]
        return !excluded.contains { lower.contains($0) }
    }

    /// The Launchpad X exposes two port pairs: "LPX DAW" (Ableton session control) and
    /// "LPX MIDI" (Programmer-mode lighting, what this app needs).
    static func looksLikeLaunchpadMIDIPort(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("launchpad") && !lower.contains("daw")
    }

    // MARK: - Manual endpoint selection

    func useManualXTouchSource(_ endpoint: MIDIEndpointRef) {
        let previous = xTouchSource
        xTouchSource = endpoint
        xTouchSourceIsManual = true
        disconnectSourceIfOrphaned(previous)
        connectSources()
        refreshStatus()
    }

    func useManualXTouchDestination(_ endpoint: MIDIEndpointRef) {
        xTouchDestination = endpoint
        xTouchDestinationIsManual = true
        refreshStatus()
    }

    func useManualLaunchpadSource(_ endpoint: MIDIEndpointRef) {
        let previous = launchpadSource
        launchpadSource = endpoint
        launchpadSourceIsManual = true
        disconnectSourceIfOrphaned(previous)
        connectSources()
        refreshStatus()
    }

    func useManualLaunchpadDestination(_ endpoint: MIDIEndpointRef) {
        launchpadDestination = endpoint
        launchpadDestinationIsManual = true
        refreshStatus()
    }

    /// Drops all manual overrides and re-runs automatic matching.
    func resetToAutomaticSelection() {
        xTouchSourceIsManual = false
        xTouchDestinationIsManual = false
        launchpadSourceIsManual = false
        launchpadDestinationIsManual = false
        discoverDevices()
    }

    var hasManualSelection: Bool {
        xTouchSourceIsManual || xTouchDestinationIsManual
            || launchpadSourceIsManual || launchpadDestinationIsManual
    }

    // MARK: - Endpoint metadata

    private func endpointInfo(for endpoint: MIDIEndpointRef) -> MIDIEndpointInfo {
        MIDIEndpointInfo(
            id: uniqueID(for: endpoint),
            endpointRef: endpoint,
            displayName: stringProperty(kMIDIPropertyDisplayName, of: endpoint),
            manufacturer: stringProperty(kMIDIPropertyManufacturer, of: endpoint),
            model: stringProperty(kMIDIPropertyModel, of: endpoint)
        )
    }

    private func uniqueID(for endpoint: MIDIEndpointRef) -> MIDIUniqueID {
        var value: MIDIUniqueID = 0
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &value)
        return value
    }

    private func stringProperty(_ property: CFString, of endpoint: MIDIEndpointRef) -> String {
        var unmanaged: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, property, &unmanaged)
        guard status == noErr, let unmanaged else { return "" }
        return unmanaged.takeRetainedValue() as String
    }
}
