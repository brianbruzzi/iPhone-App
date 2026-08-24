import Foundation

/// Which protocol a connected control surface appears to be speaking, inferred from the
/// messages it sends. The X-Touch's mode is set in a power-on menu on the unit itself, so
/// the app can't query or change it — but it *can* recognise it from the traffic, which
/// turns "nothing works and I don't know why" into a specific, actionable answer.
public enum SurfaceMode: String, Equatable, CaseIterable {
    /// Mackie Control: 14-bit pitch-bend faders. What this app targets.
    case mackieControl
    /// Standard MIDI controller mode: 7-bit CC faders.
    case ctrl
    /// HUI: the X-Touch's factory default, and incompatible with everything this app sends.
    case hui

    public var displayName: String {
        switch self {
        case .mackieControl: return "MC (Mackie Control)"
        case .ctrl: return "Ctrl (standard MIDI)"
        case .hui: return "HUI"
        }
    }

    /// Whether this app's fader automation can drive the surface in this mode.
    public var isSupported: Bool {
        switch self {
        case .mackieControl, .ctrl: return true
        case .hui: return false
        }
    }
}

/// Decodes raw MIDI bytes into human-readable descriptions for the diagnostics log, and
/// infers which protocol the surface is speaking. Pure byte inspection — no CoreMIDI
/// dependency, so it's fully unit-testable.
public enum MIDIMessageDecoder {

    /// Formats bytes as space-separated uppercase hex, e.g. "E0 00 40".
    public static func hexString(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// Splits one MIDI packet's raw bytes into individual messages by walking status
    /// bytes. CoreMIDI can — and does, e.g. when several faders move at the same
    /// timestamp — bundle multiple simultaneous messages into a single packet. CoreMIDI
    /// packets never use running status, so each message starts with its own status byte,
    /// making a straightforward walk sufficient. Any leading bytes below 0x80 (a stray
    /// data byte with no preceding status, which shouldn't occur in a well-formed packet
    /// but is not asserted against) are skipped rather than misread as a status byte.
    public static func splitMessages(_ bytes: [UInt8]) -> [[UInt8]] {
        var messages: [[UInt8]] = []
        var index = 0
        while index < bytes.count {
            let status = bytes[index]
            guard status >= 0x80 else { index += 1; continue }

            if status == 0xF0 {
                // SysEx: runs to 0xF7 (inclusive) or the end of the available bytes.
                var end = index + 1
                while end < bytes.count, bytes[end] != 0xF7 { end += 1 }
                if end < bytes.count { end += 1 }
                messages.append(Array(bytes[index..<end]))
                index = end
                continue
            }

            let length: Int
            switch status {
            case 0x80...0xBF, 0xE0...0xEF: length = 3   // note/CC/pitch-bend
            case 0xC0...0xDF: length = 2                 // program change / channel pressure
            case 0xF1, 0xF3: length = 2                  // MTC quarter frame / song select
            case 0xF2: length = 3                        // song position pointer
            default: length = 1                          // 0xF4-0xF7, 0xF8-0xFF: real-time/undefined
            }

            let end = min(index + length, bytes.count)
            messages.append(Array(bytes[index..<end]))
            index = end
        }
        return messages
    }

    /// A plain-English description of a MIDI message, favouring X-Touch/Launchpad
    /// meanings over generic MIDI ones where they apply.
    public static func describe(_ bytes: [UInt8]) -> String {
        guard let status = bytes.first else { return "empty" }

        // SysEx
        if status == 0xF0 {
            if bytes.count >= 6, Array(bytes.prefix(6)) == LaunchpadXProtocol.sysExHeader {
                return "SysEx — Launchpad X (\(bytes.count) bytes)"
            }
            if bytes.count >= 5, Array(bytes.prefix(5)) == [0xF0, 0x00, 0x00, 0x66, 0x14] {
                return "SysEx — Mackie Control / X-Touch (\(bytes.count) bytes)"
            }
            if bytes.count >= 5, Array(bytes.prefix(5)) == [0xF0, 0x00, 0x20, 0x32, 0x14] {
                return "SysEx — Behringer X-Touch, Ctrl mode (\(bytes.count) bytes)"
            }
            return "SysEx (\(bytes.count) bytes)"
        }

        guard bytes.count >= 3 else {
            return "short message (\(bytes.count) bytes)"
        }

        let channel = Int(status & 0x0F) + 1
        let kind = status & 0xF0

        switch kind {
        case 0xE0:
            let value = (Int(bytes[2]) << 7) | Int(bytes[1])
            let fader = Int(status & 0x0F)
            let label = fader == XTouchProtocol.masterFaderIndex ? "master" : "\(fader + 1)"
            return "Pitch Bend ch\(channel) = \(value) — MC fader \(label)"

        case 0x90, 0x80:
            let note = bytes[1]
            let velocity = bytes[2]
            let action = (kind == 0x90 && velocity > 0) ? "on" : "off"

            if let touch = XTouchProtocol.decodeTouch(bytes) {
                let label = touch.fader == XTouchProtocol.masterFaderIndex ? "master" : "\(touch.fader + 1)"
                return "Note \(note) \(action) — MC fader \(label) touch \(touch.touched ? "DOWN" : "UP")"
            }
            if let touch = XTouchCtrlProtocol.decodeTouch(bytes) {
                let label = touch.fader == XTouchCtrlProtocol.masterFaderIndex ? "master" : "\(touch.fader + 1)"
                return "Note \(note) \(action) — Ctrl fader \(label) touch \(touch.touched ? "DOWN" : "UP")"
            }
            if let name = mackieButtonName(forNote: note) {
                return "Note \(note) \(action) vel \(velocity) — \(name)"
            }
            return "Note \(note) \(action) vel \(velocity) (ch\(channel))"

        case 0xB0:
            let cc = bytes[1]
            let value = bytes[2]
            if let fader = XTouchCtrlProtocol.decodeFader(bytes) {
                let label = fader.fader == XTouchCtrlProtocol.masterFaderIndex ? "master" : "\(fader.fader + 1)"
                return "CC \(cc) = \(value) — Ctrl fader \(label)"
            }
            if (16...23).contains(cc) {
                let direction = (value & 0x40) != 0 ? "CCW" : "CW"
                return "CC \(cc) = \(value) — MC encoder \(cc - 15) \(direction)"
            }
            if (0x0C...0x0F).contains(cc) || (0x2C...0x2F).contains(cc) {
                return "CC \(cc) = \(value) — looks like HUI zone/port"
            }
            return "CC \(cc) = \(value) (ch\(channel))"

        case 0xD0:
            let strip = (bytes[1] >> 4) + 1
            let level = bytes[1] & 0x0F
            return "Channel Pressure — VU strip \(strip) level \(level)"

        default:
            return "status \(String(format: "0x%02X", status)) (ch\(channel))"
        }
    }

    /// Infers the surface's protocol mode from a single incoming message, if that message
    /// is distinctive enough to tell. Returns nil for messages common to several modes.
    ///
    /// Distinguishing evidence:
    /// - Pitch bend on channels 1-9 → MC (Ctrl mode never sends pitch bend for faders)
    /// - CC 70-78 → Ctrl (in MC mode those CC numbers are host→surface timecode digits,
    ///   so the surface never sends them)
    /// - Paired zone/port CCs in 0x0C-0x0F / 0x2C-0x2F → HUI's characteristic encoding
    /// - Touch notes, but **only outside the overlap**: MC touch is notes 104-112 and Ctrl
    ///   touch is 110-118, so notes 110/111/112 are genuinely ambiguous and deliberately
    ///   infer nothing rather than guessing.
    public static func inferMode(from bytes: [UInt8]) -> SurfaceMode? {
        guard let status = bytes.first, bytes.count >= 3 else { return nil }

        if status & 0xF0 == 0xE0, Int(status & 0x0F) < XTouchProtocol.faderCount {
            return .mackieControl
        }
        if XTouchCtrlProtocol.decodeFader(bytes) != nil {
            return .ctrl
        }
        if status & 0xF0 == 0xB0 {
            let cc = bytes[1]
            if (0x0C...0x0F).contains(cc) || (0x2C...0x2F).contains(cc) {
                return .hui
            }
        }

        // Touch notes: only the non-overlapping parts of each range are conclusive.
        if status == 0x90 || status == 0x80 {
            let note = bytes[1]
            let mcLow = XTouchProtocol.touchNoteBase                                        // 104
            let mcHigh = mcLow + UInt8(XTouchProtocol.faderCount - 1)                       // 112
            let ctrlLow = XTouchCtrlProtocol.touchNoteBase                                  // 110
            let ctrlHigh = ctrlLow + UInt8(XTouchCtrlProtocol.faderCount - 1)               // 118

            if note >= mcLow, note < ctrlLow { return .mackieControl }
            if note > mcHigh, note <= ctrlHigh { return .ctrl }
        }

        return nil
    }

    /// Names for the Mackie Control button notes worth recognising in the log. Not
    /// exhaustive — just the ones a user is likely to press while testing.
    static func mackieButtonName(forNote note: UInt8) -> String? {
        switch note {
        case 0...7: return "MC REC/arm \(note + 1)"
        case 8...15: return "MC SOLO \(note - 7)"
        case 16...23: return "MC MUTE \(note - 15)"
        case 24...31: return "MC SELECT \(note - 23)"
        case 32...39: return "MC V-Pot press \(note - 31)"
        case 91: return "MC Rewind"
        case 92: return "MC Fast Forward"
        case 93: return "MC Stop"
        case 94: return "MC Play"
        case 95: return "MC Record"
        default: return nil
        }
    }
}
