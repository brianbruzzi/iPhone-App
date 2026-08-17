import CoreMIDI
import Observation
import FaderLabCore

enum MIDIManagerError: Error {
    case clientCreationFailed(OSStatus)
    case portCreationFailed(OSStatus)
}

/// Owns all CoreMIDI I/O: discovers the X-Touch and Launchpad X ("LPX MIDI", not "LPX
/// DAW" — see `LaunchpadXProtocol`) by name, sends fader/lighting frames to them, and
/// decodes incoming X-Touch touch-sense/position messages. This is the only file in the
/// app that imports CoreMIDI; everything else works with plain values.
@Observable
final class MIDIManager {
    private(set) var xTouchConnected = false
    private(set) var launchpadConnected = false

    /// Fired (on the main queue) when the user touches/releases a physical fader.
    var onXTouchFaderTouch: ((_ faderIndex: Int, _ touched: Bool) -> Void)?
    /// Fired (on the main queue) with live position feedback from the X-Touch.
    var onXTouchFaderPositionReport: ((_ faderIndex: Int, _ value14: Int) -> Void)?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()

    private var xTouchSource: MIDIEndpointRef?
    private var xTouchDestination: MIDIEndpointRef?
    private var launchpadSource: MIDIEndpointRef?
    private var launchpadDestination: MIDIEndpointRef?

    /// Sentinel connRefCon tokens so the single input port's read block can tell which
    /// physical device a packet list came from.
    private static let xTouchConnRefCon = UnsafeMutableRawPointer(bitPattern: 1)
    private static let launchpadConnRefCon = UnsafeMutableRawPointer(bitPattern: 2)

    // MARK: - Lifecycle

    func start() throws {
        var newClient = MIDIClientRef()
        let clientStatus = MIDIClientCreateWithBlock("FaderLab" as CFString, &newClient) { [weak self] _ in
            DispatchQueue.main.async { self?.discoverDevices() }
        }
        guard clientStatus == noErr else { throw MIDIManagerError.clientCreationFailed(clientStatus) }
        client = newClient

        var newInputPort = MIDIPortRef()
        let inputStatus = MIDIInputPortCreateWithBlock(client, "FaderLab Input" as CFString, &newInputPort) { [weak self] packetList, connRefCon in
            guard let self, connRefCon == MIDIManager.xTouchConnRefCon else { return }
            self.handleXTouchIncoming(packetList)
        }
        guard inputStatus == noErr else { throw MIDIManagerError.portCreationFailed(inputStatus) }
        inputPort = newInputPort

        var newOutputPort = MIDIPortRef()
        let outputStatus = MIDIOutputPortCreate(client, "FaderLab Output" as CFString, &newOutputPort)
        guard outputStatus == noErr else { throw MIDIManagerError.portCreationFailed(outputStatus) }
        outputPort = newOutputPort

        discoverDevices()
    }

    /// Leaves the Launchpad in a clean state and tears down the CoreMIDI client. Best
    /// effort only — SwiftUI apps don't guarantee this runs on every quit path (e.g. a
    /// force-quit), so it isn't a substitute for the Launchpad's own power-cycle reset.
    func stop() {
        if launchpadConnected {
            send(LaunchpadXProtocol.clearAllMessage(), to: launchpadDestination)
            send(LaunchpadXProtocol.programmerModeMessage(enabled: false), to: launchpadDestination)
        }
        if client != 0 {
            MIDIClientDispose(client)
            client = MIDIClientRef()
        }
        xTouchConnected = false
        launchpadConnected = false
    }

    // MARK: - Outbound

    func sendXTouchFaderPosition(fader: Int, value14: Int) {
        send(XTouchProtocol.pitchBendBytes(fader: fader, value14: value14), to: xTouchDestination)
    }

    func sendLaunchpadFrame(_ grid: PixelGrid) {
        send(LaunchpadXProtocol.frameMessage(grid), to: launchpadDestination)
    }

    func sendLaunchpadProgrammerMode(_ enabled: Bool) {
        send(LaunchpadXProtocol.programmerModeMessage(enabled: enabled), to: launchpadDestination)
    }

    func sendLaunchpadClearAll() {
        send(LaunchpadXProtocol.clearAllMessage(), to: launchpadDestination)
    }

    private func send(_ bytes: [UInt8], to destination: MIDIEndpointRef?) {
        guard let destination, outputPort != 0 else { return }

        let bufferSize = 512
        let packetListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: bufferSize,
            alignment: MemoryLayout<MIDIPacketList>.alignment
        )
        defer { packetListPointer.deallocate() }

        let packetList = packetListPointer.assumingMemoryBound(to: MIDIPacketList.self)
        var packet = MIDIPacketListInit(packetList)
        packet = MIDIPacketListAdd(packetList, bufferSize, packet, 0, bytes.count, bytes)
        guard packet != nil else { return }

        MIDISend(outputPort, destination, packetList)
    }

    // MARK: - Inbound

    private func handleXTouchIncoming(_ packetListPointer: UnsafePointer<MIDIPacketList>) {
        let numPackets = Int(packetListPointer.pointee.numPackets)
        var packet = packetListPointer.pointee.packet

        for index in 0..<numPackets {
            let length = Int(packet.length)
            let bytes: [UInt8] = withUnsafeBytes(of: packet.data) { raw in
                Array(raw.prefix(length))
            }

            if let touch = XTouchProtocol.decodeTouch(bytes) {
                DispatchQueue.main.async { [weak self] in
                    self?.onXTouchFaderTouch?(touch.fader, touch.touched)
                }
            } else if let position = XTouchProtocol.decodePitchBend(bytes) {
                DispatchQueue.main.async { [weak self] in
                    self?.onXTouchFaderPositionReport?(position.fader, position.value14)
                }
            }

            if index < numPackets - 1 {
                packet = withUnsafeMutablePointer(to: &packet) { MIDIPacketNext($0) }.pointee
            }
        }
    }

    // MARK: - Device discovery

    private func discoverDevices() {
        let sourceCount = MIDIGetNumberOfSources()
        var foundXTouchSource: MIDIEndpointRef?
        var foundLaunchpadSource: MIDIEndpointRef?
        for i in 0..<sourceCount {
            let endpoint = MIDIGetSource(i)
            let name = displayName(for: endpoint)
            if MIDIManager.looksLikeXTouch(name) {
                foundXTouchSource = endpoint
            } else if MIDIManager.looksLikeLaunchpadMIDIPort(name) {
                foundLaunchpadSource = endpoint
            }
        }

        let destinationCount = MIDIGetNumberOfDestinations()
        var foundXTouchDestination: MIDIEndpointRef?
        var foundLaunchpadDestination: MIDIEndpointRef?
        for i in 0..<destinationCount {
            let endpoint = MIDIGetDestination(i)
            let name = displayName(for: endpoint)
            if MIDIManager.looksLikeXTouch(name) {
                foundXTouchDestination = endpoint
            } else if MIDIManager.looksLikeLaunchpadMIDIPort(name) {
                foundLaunchpadDestination = endpoint
            }
        }

        xTouchSource = foundXTouchSource
        xTouchDestination = foundXTouchDestination
        launchpadSource = foundLaunchpadSource
        launchpadDestination = foundLaunchpadDestination

        reconnectInputs()

        let wasLaunchpadConnected = launchpadConnected
        xTouchConnected = xTouchSource != nil && xTouchDestination != nil
        launchpadConnected = launchpadSource != nil && launchpadDestination != nil

        if launchpadConnected, !wasLaunchpadConnected {
            sendLaunchpadProgrammerMode(true)
        }
    }

    private func reconnectInputs() {
        guard inputPort != 0 else { return }
        if let xTouchSource {
            MIDIPortConnectSource(inputPort, xTouchSource, MIDIManager.xTouchConnRefCon)
        }
        if let launchpadSource {
            MIDIPortConnectSource(inputPort, launchpadSource, MIDIManager.launchpadConnRefCon)
        }
    }

    private static func looksLikeXTouch(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("x-touch") || lower.contains("xtouch")
    }

    private static func looksLikeLaunchpadMIDIPort(_ name: String) -> Bool {
        let lower = name.lowercased()
        // The Launchpad X exposes two port pairs — "LPX MIDI" (Programmer Mode lighting,
        // what we want) and "LPX DAW" (Ableton session control). Explicitly exclude DAW.
        return lower.contains("launchpad x") && !lower.contains("daw")
    }

    // MARK: - Manual endpoint selection (fallback when auto-discovery is ambiguous)

    var availableSourceNames: [String] {
        (0..<MIDIGetNumberOfSources()).map { displayName(for: MIDIGetSource($0)) }
    }

    var availableDestinationNames: [String] {
        (0..<MIDIGetNumberOfDestinations()).map { displayName(for: MIDIGetDestination($0)) }
    }

    func useManualXTouch(sourceName: String?, destinationName: String?) {
        if let sourceName, let match = findSource(named: sourceName) { xTouchSource = match }
        if let destinationName, let match = findDestination(named: destinationName) { xTouchDestination = match }
        reconnectInputs()
        xTouchConnected = xTouchSource != nil && xTouchDestination != nil
    }

    func useManualLaunchpad(sourceName: String?, destinationName: String?) {
        if let sourceName, let match = findSource(named: sourceName) { launchpadSource = match }
        if let destinationName, let match = findDestination(named: destinationName) { launchpadDestination = match }
        reconnectInputs()
        launchpadConnected = launchpadSource != nil && launchpadDestination != nil
        if launchpadConnected {
            sendLaunchpadProgrammerMode(true)
        }
    }

    private func findSource(named name: String) -> MIDIEndpointRef? {
        let count = MIDIGetNumberOfSources()
        for i in 0..<count {
            let endpoint = MIDIGetSource(i)
            if displayName(for: endpoint) == name { return endpoint }
        }
        return nil
    }

    private func findDestination(named name: String) -> MIDIEndpointRef? {
        let count = MIDIGetNumberOfDestinations()
        for i in 0..<count {
            let endpoint = MIDIGetDestination(i)
            if displayName(for: endpoint) == name { return endpoint }
        }
        return nil
    }

    private func displayName(for endpoint: MIDIEndpointRef) -> String {
        var unmanagedName: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &unmanagedName)
        guard status == noErr, let unmanagedName else { return "" }
        return unmanagedName.takeRetainedValue() as String
    }
}
