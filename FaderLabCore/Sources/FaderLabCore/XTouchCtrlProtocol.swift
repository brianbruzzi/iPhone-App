import Foundation

/// Encodes/decodes the Behringer X-Touch's **Ctrl (standard MIDI) mode** protocol, per
/// Behringer's official "X-TOUCH / X-TOUCH EXTENDER MIDI Mode Implementation" document.
///
/// This exists as a fallback so the app does something useful even when the surface
/// hasn't been switched into MC mode. MC mode (see `XTouchProtocol`) remains the
/// preferred target — it gives 14-bit fader resolution, scribble strips, and encoder LED
/// rings, none of which Ctrl mode exposes as richly.
///
/// The two modes are mutually exclusive on the hardware, and their message maps do not
/// overlap: in Ctrl mode faders are 7-bit CCs, not pitch bend.
public enum XTouchCtrlProtocol {
    /// 8 channel strips plus the master fader, matching `XTouchProtocol.faderCount`.
    public static let faderCount = 9
    public static let masterFaderIndex = 8

    // MARK: - Faders: CC 70...78 on channel 1, 7-bit

    /// CC number for fader 1. Faders 1-8 are CC 70-77; the master fader is CC 78.
    public static let faderCCBase: UInt8 = 70
    private static let controlChangeStatusChannel1: UInt8 = 0xB0

    /// Encodes a control-change message setting `fader` (0..<faderCount) to `value7`
    /// (0...127, where 0 = fully down and 127 = fully up).
    public static func faderBytes(fader: Int, value7: Int) -> [UInt8] {
        precondition((0..<faderCount).contains(fader), "fader index out of range: \(fader)")
        let clamped = UInt8(min(max(value7, 0), 127))
        return [controlChangeStatusChannel1, faderCCBase + UInt8(fader), clamped]
    }

    /// Convenience overload taking a normalized 0...1 fader position.
    public static func faderBytes(fader: Int, unitValue: Double) -> [UInt8] {
        faderBytes(fader: fader, value7: value7(fromUnit: unitValue))
    }

    public struct FaderPositionReport: Equatable {
        public let fader: Int
        public let value7: Int

        public init(fader: Int, value7: Int) {
            self.fader = fader
            self.value7 = value7
        }
    }

    /// Decodes an incoming control-change message into a fader index + 7-bit value.
    /// Returns nil for anything that isn't a channel-1 CC in the fader range.
    public static func decodeFader(_ bytes: [UInt8]) -> FaderPositionReport? {
        guard bytes.count == 3, bytes[0] == controlChangeStatusChannel1 else { return nil }
        let cc = bytes[1]
        let ccRange = faderCCBase...(faderCCBase + UInt8(faderCount - 1))
        guard ccRange.contains(cc) else { return nil }
        return FaderPositionReport(fader: Int(cc - faderCCBase), value7: Int(bytes[2]))
    }

    // MARK: - Fader touch: notes 110...118 on channel 1

    /// Note number for fader 1's touch sense. Faders 1-8 are notes 110-117; master is 118.
    /// (Distinct from MC mode, where touch sense lives at notes 104-112.)
    public static let touchNoteBase: UInt8 = 110
    private static let noteOnStatusChannel1: UInt8 = 0x90
    private static let noteOffStatusChannel1: UInt8 = 0x80

    /// Decodes an incoming note message into a fader-touch event. Returns nil for
    /// anything that isn't a channel-1 note in the touch range.
    public static func decodeTouch(_ bytes: [UInt8]) -> XTouchProtocol.FaderTouchEvent? {
        guard bytes.count == 3 else { return nil }
        let status = bytes[0]
        guard status == noteOnStatusChannel1 || status == noteOffStatusChannel1 else { return nil }
        let note = bytes[1]
        let touchRange = touchNoteBase...(touchNoteBase + UInt8(faderCount - 1))
        guard touchRange.contains(note) else { return nil }
        let touched = status == noteOnStatusChannel1 && bytes[2] > 0
        return XTouchProtocol.FaderTouchEvent(fader: Int(note - touchNoteBase), touched: touched)
    }

    // MARK: - Button LEDs: Note On 0...103 on channel 1

    public enum ButtonLEDState {
        case off
        case flash
        case on

        /// Ctrl mode velocity encoding: 0-63 off, exactly 64 flash, 65-127 on.
        var velocity: UInt8 {
            switch self {
            case .off: return 0
            case .flash: return 64
            case .on: return 127
            }
        }
    }

    /// Encodes a button-LED message. `note` is 0...103 per Behringer's button map.
    public static func buttonLEDBytes(note: UInt8, state: ButtonLEDState) -> [UInt8] {
        precondition(note <= 103, "Ctrl-mode button notes are 0...103, got \(note)")
        return [noteOnStatusChannel1, note, state.velocity]
    }

    // MARK: - Unit <-> 7-bit conversion helpers

    public static func value7(fromUnit unit: Double) -> Int {
        Int((min(max(unit, 0), 1) * 127).rounded())
    }

    public static func unit(fromValue7 value7: Int) -> Double {
        Double(min(max(value7, 0), 127)) / 127.0
    }
}
