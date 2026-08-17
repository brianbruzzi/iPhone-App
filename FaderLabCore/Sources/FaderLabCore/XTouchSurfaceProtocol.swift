import Foundation

/// Encodes the Behringer X-Touch's MC-mode surface elements beyond faders: button LEDs,
/// the 8 encoder LED rings, and the 8 scribble-strip mini-displays (text + background
/// color). Sourced from the Mackie Control Universal protocol (button/ring encoding,
/// consistent across TouchMCU's hardware-validated reference and DrivenByMoss) and
/// Behringer's X-Touch-specific scribble-strip color extension.
///
/// MC mode only — Ctrl-mode button LEDs use a different velocity scheme, see
/// `XTouchCtrlProtocol.ButtonLEDState`.
///
/// This type is pure byte math — no CoreMIDI dependency — so it is fully unit-testable.
public enum XTouchSurfaceProtocol {
    public static let stripCount = 8

    // MARK: - Button LEDs: Note On, channel 1

    public enum ButtonLEDState: UInt8, CaseIterable, Sendable {
        case off = 0x00
        case blink = 0x01
        case solid = 0x7F
    }

    private static let noteOnStatusChannel1: UInt8 = 0x90

    /// Encodes a button-LED message. `note` is 0...103 per the MC button map (see
    /// `ButtonZone` for the specific ranges this app animates).
    public static func buttonLEDBytes(note: UInt8, state: ButtonLEDState) -> [UInt8] {
        [noteOnStatusChannel1, note, state.rawValue]
    }

    /// Groups of button notes worth animating. Not the full MC button map — just the
    /// zones with an obvious visual role on the physical surface.
    public enum ButtonZone: CaseIterable, Sendable {
        case rec
        case solo
        case mute
        case select
        case vpotPress
        case function
        case transport

        public var notes: [UInt8] {
            switch self {
            case .rec: return Array(0...7)
            case .solo: return Array(8...15)
            case .mute: return Array(16...23)
            case .select: return Array(24...31)
            case .vpotPress: return Array(32...39)
            case .function: return Array(54...61)
            case .transport: return Array(91...95)
            }
        }
    }

    /// Every animatable button note, ascending, across all zones (53 notes). This is the
    /// canonical order `SurfaceFrame.buttons` is indexed by.
    public static let animatableButtonNotes: [UInt8] = ButtonZone.allCases.flatMap { $0.notes }.sorted()

    /// The `SurfaceFrame.buttons` index for a given hardware note, or nil if that note
    /// isn't one of `animatableButtonNotes`.
    public static func buttonIndex(forNote note: UInt8) -> Int? {
        animatableButtonNotes.firstIndex(of: note)
    }

    // MARK: - Encoder LED rings: Control Change, channel 1

    public static let ringCCBase: UInt8 = 48
    private static let controlChangeStatusChannel1: UInt8 = 0xB0

    /// How the 13-segment ring around each encoder displays its position.
    public enum RingMode: UInt8, CaseIterable, Sendable {
        case dot = 0b00       // single lit segment
        case boostCut = 0b01  // fills from center outward
        case wrap = 0b10      // fills from the left, like a bar
        case spread = 0b11    // fills outward from center in both directions
    }

    public struct RingDisplay: Equatable, Sendable {
        public var mode: RingMode
        /// 0 = ring dark, 1...11 = how many segments are lit. Values outside 0...11 are
        /// clamped when encoded.
        public var position: Int
        public var centerLED: Bool

        public init(mode: RingMode = .dot, position: Int = 0, centerLED: Bool = false) {
            self.mode = mode
            self.position = position
            self.centerLED = centerLED
        }

        public static let off = RingDisplay()
    }

    /// Packs a ring display into MC's single-byte encoding: bit6 = center LED, bits5-4 =
    /// mode, bits3-0 = position (0x00...0x0B).
    public static func ringValueByte(_ display: RingDisplay) -> UInt8 {
        let clampedPosition = UInt8(min(max(display.position, 0), 11))
        let centerBit: UInt8 = display.centerLED ? 0x40 : 0x00
        let modeBits: UInt8 = display.mode.rawValue << 4
        return centerBit | modeBits | clampedPosition
    }

    /// Encodes a ring-display message for `strip` (0...7).
    public static func ringBytes(strip: Int, display: RingDisplay) -> [UInt8] {
        precondition((0..<stripCount).contains(strip), "strip index out of range: \(strip)")
        return [controlChangeStatusChannel1, ringCCBase + UInt8(strip), ringValueByte(display)]
    }

    // MARK: - Scribble strips: SysEx F0 00 00 66 14 <cmd> ... F7

    public static let scribbleSysExHeader: [UInt8] = [0xF0, 0x00, 0x00, 0x66, 0x14]
    private static let sysExTerminator: UInt8 = 0xF7
    private static let updateLCDCommand: UInt8 = 0x12
    private static let scribbleColorCommand: UInt8 = 0x72
    private static let channelMeterModeCommand: UInt8 = 0x20

    public static let scribbleCharsPerCell = 7

    public enum ScribbleRow: CaseIterable, Sendable {
        case upper
        case lower
    }

    /// The X-Touch's scribble-strip background color extension. Requires firmware ≥1.22;
    /// older firmware silently ignores the message, which degrades gracefully with no
    /// special-casing needed here.
    public enum ScribbleColor: UInt8, CaseIterable, Sendable {
        case black = 0
        case red = 1
        case green = 2
        case yellow = 3
        case blue = 4
        case magenta = 5
        case cyan = 6
        case white = 7
    }

    /// Encodes exactly `scribbleCharsPerCell` (7) characters of text for one strip's
    /// upper or lower row. Non-ASCII-printable characters (outside 0x20...0x7E) become
    /// spaces; shorter text is space-padded, longer text is truncated.
    public static func scribbleTextMessage(strip: Int, row: ScribbleRow, text: String) -> [UInt8] {
        precondition((0..<stripCount).contains(strip), "strip index out of range: \(strip)")
        let offset = (row == .upper ? 0 : 56) + strip * scribbleCharsPerCell

        var chars: [UInt8] = text.unicodeScalars.prefix(scribbleCharsPerCell).map { scalar in
            (scalar.value >= 0x20 && scalar.value <= 0x7E) ? UInt8(scalar.value) : 0x20
        }
        while chars.count < scribbleCharsPerCell {
            chars.append(0x20)
        }

        return scribbleSysExHeader + [updateLCDCommand, UInt8(offset)] + chars + [sysExTerminator]
    }

    /// Encodes the background color for all 8 strips in one message — the hardware only
    /// accepts this all-or-nothing, there's no per-strip color command.
    public static func scribbleColorsMessage(_ colors: [ScribbleColor]) -> [UInt8] {
        precondition(colors.count == stripCount, "expected exactly \(stripCount) colors, got \(colors.count)")
        return scribbleSysExHeader + [scribbleColorCommand] + colors.map { $0.rawValue } + [sysExTerminator]
    }

    /// SysEx command `0x04` is the surface's handshake-error response, and sending it
    /// (rather than only ever receiving it) is documented to brick the session — real
    /// hardware has been observed to display "SECURITY UNLOCK FAILED SHUTTING DOWN" and
    /// stop responding. Nothing in this file may construct a message using this command;
    /// see `XTouchSurfaceProtocolTests` for the enforcing test.
    public static let forbiddenSysExCommand: UInt8 = 0x04

    // MARK: - VU meters (byte encoders only — not wired into SurfaceFrame this round;
    // their ~0.4s auto-decay requires periodic resending regardless of change, which
    // doesn't fit the diff-only "resend only what changed" model the rest of this file
    // follows. Included now so a future round doesn't have to re-derive the protocol.)

    /// Channel Pressure, packing strip (high nibble) and level (low nibble) into one byte.
    /// `level` 0...12 = -60dB...0dB in the surface's fixed table, 13 = >0dB (clamped).
    public static func vuLevelBytes(strip: Int, level: Int) -> [UInt8] {
        precondition((0..<stripCount).contains(strip), "strip index out of range: \(strip)")
        let clampedLevel = UInt8(min(max(level, 0), 0x0D))
        return [0xD0, (UInt8(strip) << 4) | clampedLevel]
    }

    /// Enables/disables the strip's dedicated LED-only VU meter (mode byte `0x01`).
    public static func vuEnableMessage(strip: Int, enabled: Bool) -> [UInt8] {
        precondition((0..<stripCount).contains(strip), "strip index out of range: \(strip)")
        let mode: UInt8 = enabled ? 0x01 : 0x00
        return scribbleSysExHeader + [channelMeterModeCommand, UInt8(strip), mode] + [sysExTerminator]
    }
}
