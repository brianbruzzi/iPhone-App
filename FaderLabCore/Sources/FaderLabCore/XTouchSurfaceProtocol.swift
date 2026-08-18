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

    /// Encodes a button-LED message. `note` is 0...103, or one of the LED-only indicator
    /// notes 113...115 (see `ButtonZone` for the specific ranges this app animates).
    public static func buttonLEDBytes(note: UInt8, state: ButtonLEDState) -> [UInt8] {
        [noteOnStatusChannel1, note, state.rawValue]
    }

    /// Groups of button notes worth animating. Not the full MC button map — just the
    /// zones with an obvious visual role on the physical surface.
    ///
    /// The 9 cases from `assign` through `userSwitch` cover the X-Touch's right-hand
    /// control section (assign row, bank/channel nav, the Flip/Global-View toggles, the
    /// Global View row, modifier keys, automation modes, utility buttons, and the cursor
    /// cluster). Note numbers are confirmed against a reverse-engineered per-button X-Touch
    /// table (cross-checked against 3 independent MCU implementations and Ardour's own
    /// surface driver) — every button on the surface has a working LED except two
    /// (`.miscToggles` deliberately excludes them, see below). None of this carries
    /// hardware risk either way: these are plain Note On messages, and a note the surface
    /// doesn't implement is simply ignored — a fundamentally different (harmless) situation
    /// from the forbidden SysEx command below. The jog wheel deliberately has no case here:
    /// it's an input-only relative-encoder CC with no controllable LED.
    ///
    /// The assign row's note-to-label pairing (in case it's ever surfaced in the UI) is
    /// 40=TRACK, 41=SEND, 42=PAN/SURROUND, 43=PLUG-IN, 44=EQ, 45=INST — note order, not the
    /// panel's left-to-right silkscreen order.
    public enum ButtonZone: CaseIterable, Sendable {
        case rec
        case solo
        case mute
        case select
        case vpotPress
        case function
        case transport
        case assign
        case bankNav
        case miscToggles
        case globalView
        case modifier
        case automation
        case utility
        case cursor
        case userSwitch
        case indicator

        public var notes: [UInt8] {
            switch self {
            case .rec: return Array(0...7)
            case .solo: return Array(8...15)
            case .mute: return Array(16...23)
            case .select: return Array(24...31)
            case .vpotPress: return Array(32...39)
            case .function: return Array(54...61)
            case .transport: return Array(91...95)
            case .assign: return Array(40...45)
            case .bankNav: return Array(46...49)
            // Flip (50) and Global View toggle (51) only — 52 (Name/Value) and 53
            // (SMPTE/Beats) are confirmed to have no LED behind them at all, so lighting
            // them is wasted traffic that would also make a "light everything" test look
            // like it found a dead button when nothing is actually wrong.
            case .miscToggles: return Array(50...51)
            case .globalView: return Array(62...69)
            case .modifier: return Array(70...73)
            case .automation: return Array(74...79)
            case .utility: return Array(80...90)
            case .cursor: return Array(96...101)
            case .userSwitch: return Array(102...103)
            // LEDs with no button behind them (SMPTE LED, Beats LED, rude-Solo LED) —
            // free extra lights next to the timecode display. Not to be confused with
            // 104...112, which are the fader touch-sense notes, not LEDs.
            case .indicator: return Array(113...115)
            }
        }
    }

    /// Every animatable button note, ascending, across all zones (105 notes — not
    /// contiguous, since notes 52/53 and 104...112 are deliberately excluded). This is the
    /// canonical order `SurfaceFrame.buttons` is indexed by.
    public static let animatableButtonNotes: [UInt8] = ButtonZone.allCases.flatMap { $0.notes }.sorted()

    /// The `SurfaceFrame.buttons` index for a given hardware note, or nil if that note
    /// isn't one of `animatableButtonNotes`.
    public static func buttonIndex(forNote note: UInt8) -> Int? {
        animatableButtonNotes.firstIndex(of: note)
    }

    // MARK: - Section split: channel strips vs. the right-hand control cluster

    /// The 5 zones sitting directly above the 8 faders (notes 0...39) — the channel-strip
    /// section. These, plus the encoder rings and scribble strips, are the "fader show":
    /// they belong to whichever pattern is driving the channel strips.
    public static let channelStripZones: [ButtonZone] = [.rec, .solo, .mute, .select, .vpotPress]

    /// The 12 zones making up the X-Touch's right-hand control cluster — every animatable
    /// button at note 40 and above, i.e. everything that is *not* part of a channel strip.
    /// This is the seam the UI's "Other Buttons" picker owns: it can follow the fader show
    /// or run a completely independent pattern (see `PatternEngine.rightSectionPattern`).
    public static let rightSectionZones: [ButtonZone] = [
        .assign, .bankNav, .miscToggles, .function, .globalView, .modifier,
        .automation, .utility, .transport, .cursor, .userSwitch, .indicator
    ]

    /// Every right-section button note, ascending — 65 of the 105 animatable notes. The
    /// complement of `channelStripZones`' notes; `XTouchSurfaceProtocolTests` enforces that
    /// the two partition `animatableButtonNotes` exactly, so adding a zone without
    /// classifying it fails the build's tests rather than silently going dark.
    public static let rightSectionButtonNotes: [UInt8] = rightSectionZones.flatMap { $0.notes }.sorted()

    /// `SurfaceFrame.buttons` indices for `rightSectionButtonNotes`, precomputed so the
    /// per-tick splice in `PatternEngine` is a straight array copy rather than 130 linear
    /// `firstIndex(of:)` scans.
    public static let rightSectionButtonIndices: [Int] = rightSectionButtonNotes.compactMap { buttonIndex(forNote: $0) }

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

    // MARK: - VU meters
    //
    // Deliberately NOT part of `SurfaceFrame`: the hardware meters decay on their own at
    // roughly 300ms per division, so they have to be re-sent continuously even when the
    // value hasn't changed. That's the opposite of the diff-only "send only what changed"
    // model every other element here follows, so VU gets its own un-cached send path in
    // `MIDIManager` rather than being wedged into the frame diff.

    /// Level `0x0E`/`0x0F` are "set overload"/"clear overload" latches, not levels —
    /// `vuLevelBytes` clamps below them so a runaway value can never accidentally latch a
    /// clip indicator on that then needs an explicit clear to release.
    public static let vuMaxLevel = 0x0D

    /// Channel Pressure, packing strip (high nibble) and level (low nibble) into one byte.
    /// `level` 0...12 = -60dB...0dB in the surface's fixed table, 13 = >0dB (clamped).
    public static func vuLevelBytes(strip: Int, level: Int) -> [UInt8] {
        precondition((0..<stripCount).contains(strip), "strip index out of range: \(strip)")
        let clampedLevel = UInt8(min(max(level, 0), vuMaxLevel))
        return [0xD0, (UInt8(strip) << 4) | clampedLevel]
    }

    /// Maps a 0...1 unit value (a fader position or an audio level) onto the meter's
    /// 0...13 division scale. Linear in divisions rather than in dB: the meter's own
    /// scale is already heavily compressed at the top (0x9...0x0C covers just -6dB...0dB),
    /// so a straight linear map reads as a full, even sweep across the LEDs.
    public static func vuLevel(forUnitValue unitValue: Double) -> Int {
        guard unitValue.isFinite else { return 0 }
        let clamped = min(max(unitValue, 0), 1)
        return Int((clamped * Double(vuMaxLevel)).rounded())
    }

    /// Enables/disables the strip's dedicated LED-only VU meter (mode byte `0x01`).
    public static func vuEnableMessage(strip: Int, enabled: Bool) -> [UInt8] {
        precondition((0..<stripCount).contains(strip), "strip index out of range: \(strip)")
        let mode: UInt8 = enabled ? 0x01 : 0x00
        return scribbleSysExHeader + [channelMeterModeCommand, UInt8(strip), mode] + [sysExTerminator]
    }

    // MARK: - 7-segment display (timecode + assignment): Control Change, channel 1
    //
    // The 12-digit LED display across the top right of the surface: a 10-digit timecode
    // readout plus the 2-digit "Assignment" block to its left. Plain Control Change, so —
    // like the button notes — a digit the hardware doesn't implement is simply ignored,
    // with none of the risk the forbidden SysEx command above carries.
    //
    // Note numbers and value encoding follow the Mackie Control spec as documented by
    // TouchMCU (the same hardware-validated reference this file's button map is checked
    // against) and corroborated by libMackieControl.

    /// CC `0x40` addresses the **rightmost** digit and `0x4B` the leftmost — the display is
    /// numbered like a counter, right to left. `timecodeMessages(text:)` handles the
    /// reversal so callers can just pass ordinary left-to-right text.
    public static let displayCCBase: UInt8 = 0x40
    public static let displayDigitCount = 12

    /// Bit 6 of the value byte lights that digit's decimal point.
    private static let displayDotBit: UInt8 = 0x40

    /// The display understands ASCII `0x20...0x5F` — space, punctuation, digits, and
    /// uppercase letters — encoded as the low 6 bits of the character. Lowercase is
    /// upper-cased; anything else becomes a space.
    ///
    /// Being 7-segment, the glyphs are approximations: `M`, `W`, `K`, `V`, and `X` have no
    /// faithful 7-segment form and will render as rough stand-ins. That's a property of the
    /// hardware, not of this encoding.
    public static func displayDigitValue(for character: Character, dot: Bool = false) -> UInt8 {
        let uppercased = String(character).uppercased()
        let scalar = uppercased.unicodeScalars.first.map { $0.value } ?? 0x20
        let ascii: UInt32 = (scalar >= 0x20 && scalar <= 0x5F) ? scalar : 0x20
        return UInt8(ascii & 0x3F) | (dot ? displayDotBit : 0)
    }

    /// Encodes one digit position. `position` 0 is the **leftmost** digit (reading order),
    /// which is the opposite of the underlying CC numbering — see `displayCCBase`.
    public static func displayDigitBytes(position: Int, character: Character, dot: Bool = false) -> [UInt8] {
        precondition((0..<displayDigitCount).contains(position), "digit position out of range: \(position)")
        let cc = displayCCBase + UInt8(displayDigitCount - 1 - position)
        return [controlChangeStatusChannel1, cc, displayDigitValue(for: character, dot: dot)]
    }

    /// Encodes `text` across all 12 digits, left-aligned in reading order and space-padded
    /// (so a shorter message blanks the rest of the display rather than leaving stale
    /// characters behind). Longer text is truncated. Always returns exactly
    /// `displayDigitCount` messages.
    public static func displayTextMessages(_ text: String) -> [[UInt8]] {
        var characters = Array(text.prefix(displayDigitCount))
        while characters.count < displayDigitCount {
            characters.append(" ")
        }
        return characters.enumerated().map { position, character in
            displayDigitBytes(position: position, character: character)
        }
    }
}
