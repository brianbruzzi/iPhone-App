import Foundation

/// Encodes/decodes the Behringer X-Touch's motorized-fader protocol, which (once the
/// surface is switched into MC/Mackie Control mode on the hardware itself — a one-time
/// manual setup step, not something this code can do) is the standard Mackie Control
/// Universal fader protocol:
///
/// - Fader position is MIDI **Pitch Bend**, one MIDI channel per fader. Sending it drives
///   the motor to that position; the surface also emits it as live position feedback
///   while a fader moves (whether motor- or hand-driven), so this is bidirectional.
/// - Fader **touch** is Note On/Off on MIDI channel 1, notes 0x68...0x70 — this is how the
///   surface tells the host "the user has their hand on fader N", which callers use to
///   suspend automation for that fader so the motor doesn't fight the user.
///
/// This type is pure byte math — no CoreMIDI dependency — so it is fully unit-testable.
public enum XTouchProtocol {
    /// 8 channel strip faders (indices 0...7) plus the master fader (index 8).
    public static let faderCount = 9
    public static let masterFaderIndex = 8

    // MARK: - Fader position (bidirectional): Pitch Bend, channel = fader index

    /// Encodes a pitch-bend message that drives `fader` (0..<faderCount) to `value14`
    /// (0...16383, where 0 = fully down and 16383 = fully up).
    public static func pitchBendBytes(fader: Int, value14: Int) -> [UInt8] {
        precondition((0..<faderCount).contains(fader), "fader index out of range: \(fader)")
        let clamped = min(max(value14, 0), 16383)
        let status: UInt8 = 0xE0 | UInt8(fader)
        let lsb = UInt8(clamped & 0x7F)
        let msb = UInt8((clamped >> 7) & 0x7F)
        return [status, lsb, msb]
    }

    /// Convenience overload taking a normalized 0...1 fader position.
    public static func pitchBendBytes(fader: Int, unitValue: Double) -> [UInt8] {
        pitchBendBytes(fader: fader, value14: value14(fromUnit: unitValue))
    }

    public struct FaderPositionReport: Equatable {
        public let fader: Int
        public let value14: Int

        public init(fader: Int, value14: Int) {
            self.fader = fader
            self.value14 = value14
        }
    }

    /// Decodes an incoming 3-byte pitch-bend message into a fader index + 14-bit value.
    /// Returns nil for anything that isn't a pitch-bend message on a valid fader channel.
    public static func decodePitchBend(_ bytes: [UInt8]) -> FaderPositionReport? {
        guard bytes.count == 3 else { return nil }
        let status = bytes[0]
        guard status & 0xF0 == 0xE0 else { return nil }
        let fader = Int(status & 0x0F)
        guard fader < faderCount else { return nil }
        let value = (Int(bytes[2]) << 7) | Int(bytes[1])
        return FaderPositionReport(fader: fader, value14: value)
    }

    // MARK: - Fader touch sense (device -> host only): Note On/Off, channel 1

    /// Touch-sense notes are on channel 1: fader 1 (index 0) = 0x68 ... master (index 8) = 0x70.
    public static let touchNoteBase: UInt8 = 0x68
    private static let noteOnStatusChannel1: UInt8 = 0x90
    private static let noteOffStatusChannel1: UInt8 = 0x80

    public struct FaderTouchEvent: Equatable {
        public let fader: Int
        public let touched: Bool

        public init(fader: Int, touched: Bool) {
            self.fader = fader
            self.touched = touched
        }
    }

    /// Decodes an incoming 3-byte note on/off message into a fader-touch event. Returns
    /// nil for anything that isn't a channel-1 note message in the touch-note range.
    /// Handles both explicit Note Off (0x80) and the common Note On w/ velocity 0 convention.
    public static func decodeTouch(_ bytes: [UInt8]) -> FaderTouchEvent? {
        guard bytes.count == 3 else { return nil }
        let status = bytes[0]
        guard status == noteOnStatusChannel1 || status == noteOffStatusChannel1 else { return nil }
        let note = bytes[1]
        let velocity = bytes[2]
        let touchNoteRange = touchNoteBase...(touchNoteBase + UInt8(faderCount - 1))
        guard touchNoteRange.contains(note) else { return nil }
        let fader = Int(note - touchNoteBase)
        let touched = status == noteOnStatusChannel1 && velocity > 0
        return FaderTouchEvent(fader: fader, touched: touched)
    }

    // MARK: - Unit <-> 14-bit conversion helpers

    public static func value14(fromUnit unit: Double) -> Int {
        Int((min(max(unit, 0), 1) * 16383).rounded())
    }

    public static func unit(fromValue14 value14: Int) -> Double {
        Double(min(max(value14, 0), 16383)) / 16383.0
    }
}
