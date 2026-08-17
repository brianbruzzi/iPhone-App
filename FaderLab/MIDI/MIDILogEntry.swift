import Foundation
import FaderLabCore

/// One line in the diagnostics MIDI log.
struct MIDILogEntry: Identifiable, Equatable {
    enum Direction: String {
        case incoming = "IN"
        case outgoing = "OUT"
    }

    let id = UUID()
    let direction: Direction
    let timestamp: Date
    let hex: String
    let description: String

    init(direction: Direction, bytes: [UInt8], timestamp: Date = Date()) {
        self.direction = direction
        self.timestamp = timestamp
        self.hex = MIDIMessageDecoder.hexString(bytes)
        self.description = MIDIMessageDecoder.describe(bytes)
    }

    var formattedTime: String {
        MIDILogEntry.timeFormatter.string(from: timestamp)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

/// A bounded ring buffer of MIDI traffic for the diagnostics panel. Outgoing traffic runs
/// at ~270 messages/second, so it is sampled rather than logged in full — the log exists to
/// show *what kind* of thing is being sent, not to be a complete capture.
@Observable
final class MIDIMonitor {
    private(set) var entries: [MIDILogEntry] = []
    var isPaused = false

    /// Which protocol the connected surface appears to be speaking, inferred from
    /// incoming traffic. Nil until something conclusive arrives.
    private(set) var detectedMode: SurfaceMode?

    private let capacity = 200
    private var outgoingSampleCounter = 0
    /// Log roughly one in N outgoing messages so the fader stream doesn't drown everything.
    private let outgoingSampleRate = 60

    func recordIncoming(_ bytes: [UInt8]) {
        if let mode = MIDIMessageDecoder.inferMode(from: bytes) {
            detectedMode = mode
        }
        guard !isPaused else { return }
        append(MIDILogEntry(direction: .incoming, bytes: bytes))
    }

    func recordOutgoing(_ bytes: [UInt8], force: Bool = false) {
        guard !isPaused else { return }
        if !force {
            outgoingSampleCounter += 1
            guard outgoingSampleCounter >= outgoingSampleRate else { return }
            outgoingSampleCounter = 0
        }
        append(MIDILogEntry(direction: .outgoing, bytes: bytes))
    }

    func clear() {
        entries.removeAll()
    }

    func resetDetectedMode() {
        detectedMode = nil
    }

    private func append(_ entry: MIDILogEntry) {
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }
}
