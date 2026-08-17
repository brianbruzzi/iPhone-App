import XCTest
@testable import FaderLabCore

final class MIDIMessageDecoderTests: XCTestCase {

    // MARK: - Hex formatting

    func testHexString() {
        XCTAssertEqual(MIDIMessageDecoder.hexString([0xE0, 0x00, 0x40]), "E0 00 40")
        XCTAssertEqual(MIDIMessageDecoder.hexString([0x00, 0xFF]), "00 FF")
        XCTAssertEqual(MIDIMessageDecoder.hexString([]), "")
    }

    // MARK: - Mode inference — the whole point of the diagnostics panel

    func testInfersMackieControlFromPitchBend() {
        XCTAssertEqual(MIDIMessageDecoder.inferMode(from: [0xE0, 0x00, 0x40]), .mackieControl)
        XCTAssertEqual(MIDIMessageDecoder.inferMode(from: [0xE8, 0x7F, 0x7F]), .mackieControl)
    }

    func testInfersMackieControlFromUnambiguousTouchNote() {
        // Notes 104-109 are MC-only (Ctrl's touch range starts at 110).
        XCTAssertEqual(MIDIMessageDecoder.inferMode(from: [0x90, 104, 127]), .mackieControl)
        XCTAssertEqual(MIDIMessageDecoder.inferMode(from: [0x90, 109, 127]), .mackieControl)
    }

    func testInfersCtrlFromFaderCC() {
        XCTAssertEqual(MIDIMessageDecoder.inferMode(from: [0xB0, 70, 64]), .ctrl)
        XCTAssertEqual(MIDIMessageDecoder.inferMode(from: [0xB0, 78, 64]), .ctrl)
    }

    func testInfersCtrlFromUnambiguousTouchNote() {
        // Notes 113-118 are Ctrl-only (MC's touch range ends at 112).
        XCTAssertEqual(MIDIMessageDecoder.inferMode(from: [0x90, 113, 127]), .ctrl)
        XCTAssertEqual(MIDIMessageDecoder.inferMode(from: [0x90, 118, 127]), .ctrl)
    }

    func testOverlappingTouchNotesInferNothing() {
        // MC touch is notes 104-112, Ctrl touch is 110-118 — 110/111/112 belong to both,
        // so they must not be used to guess a mode.
        for note: UInt8 in 110...112 {
            XCTAssertNil(
                MIDIMessageDecoder.inferMode(from: [0x90, note, 127]),
                "note \(note) is ambiguous between MC and Ctrl and must not infer a mode"
            )
        }
    }

    func testInfersHUIFromZonePortCC() {
        XCTAssertEqual(MIDIMessageDecoder.inferMode(from: [0xB0, 0x0C, 0x40]), .hui)
        XCTAssertEqual(MIDIMessageDecoder.inferMode(from: [0xB0, 0x2C, 0x40]), .hui)
    }

    func testInferReturnsNilForAmbiguousMessages() {
        // A plain middle-C note tells us nothing about the surface's mode.
        XCTAssertNil(MIDIMessageDecoder.inferMode(from: [0x90, 60, 100]))
        XCTAssertNil(MIDIMessageDecoder.inferMode(from: [0xB0, 7, 100]))
        XCTAssertNil(MIDIMessageDecoder.inferMode(from: []))
        XCTAssertNil(MIDIMessageDecoder.inferMode(from: [0xF0]))
    }

    func testModeSupportFlags() {
        XCTAssertTrue(SurfaceMode.mackieControl.isSupported)
        XCTAssertTrue(SurfaceMode.ctrl.isSupported)
        XCTAssertFalse(SurfaceMode.hui.isSupported, "HUI is the failure case we're diagnosing")
    }

    // MARK: - Descriptions

    func testDescribesPitchBendAsMCFader() {
        let text = MIDIMessageDecoder.describe([0xE0, 0x00, 0x40])
        XCTAssertTrue(text.contains("Pitch Bend"), text)
        XCTAssertTrue(text.contains("MC fader 1"), text)
    }

    func testDescribesMasterPitchBend() {
        let text = MIDIMessageDecoder.describe([0xE8, 0x00, 0x40])
        XCTAssertTrue(text.contains("master"), text)
    }

    func testDescribesMCFaderTouch() {
        let text = MIDIMessageDecoder.describe([0x90, 104, 127])
        XCTAssertTrue(text.contains("MC fader 1 touch DOWN"), text)
    }

    func testDescribesCtrlFader() {
        let text = MIDIMessageDecoder.describe([0xB0, 70, 64])
        XCTAssertTrue(text.contains("Ctrl fader 1"), text)
    }

    func testDescribesNamedMackieButton() {
        let text = MIDIMessageDecoder.describe([0x90, 24, 127])
        XCTAssertTrue(text.contains("MC SELECT 1"), text)

        let play = MIDIMessageDecoder.describe([0x90, 94, 127])
        XCTAssertTrue(play.contains("MC Play"), play)
    }

    func testDescribesLaunchpadSysEx() {
        let message = LaunchpadXProtocol.programmerModeMessage(enabled: true)
        let text = MIDIMessageDecoder.describe(message)
        XCTAssertTrue(text.contains("Launchpad X"), text)
    }

    func testDescribesMackieSysEx() {
        let text = MIDIMessageDecoder.describe([0xF0, 0x00, 0x00, 0x66, 0x14, 0x12, 0x00, 0xF7])
        XCTAssertTrue(text.contains("Mackie Control"), text)
    }

    func testDescribesEmptyAndShortMessagesWithoutCrashing() {
        XCTAssertEqual(MIDIMessageDecoder.describe([]), "empty")
        XCTAssertTrue(MIDIMessageDecoder.describe([0x90, 60]).contains("short"))
    }

    func testDescribesVUMeterChannelPressure() {
        let text = MIDIMessageDecoder.describe([0xD0, 0x7C, 0x00])
        XCTAssertTrue(text.contains("VU strip 8"), text)
    }

    // MARK: - splitMessages — the packet-coalescing bug this exists to fix

    func testSplitsTwoCoalescedFaderMessages() {
        // Exactly the real-world case that motivated this: two faders moved at the same
        // timestamp, so CoreMIDI packs both pitch-bend messages into one packet.
        let fader1 = XTouchProtocol.pitchBendBytes(fader: 0, value14: 8000)
        let fader2 = XTouchProtocol.pitchBendBytes(fader: 1, value14: 12000)
        let packetBytes = fader1 + fader2

        let messages = MIDIMessageDecoder.splitMessages(packetBytes)

        XCTAssertEqual(messages, [fader1, fader2])
    }

    func testSplitsNineCoalescedFaderMessages() {
        let allNine = (0..<XTouchProtocol.faderCount).map {
            XTouchProtocol.pitchBendBytes(fader: $0, value14: $0 * 1000)
        }
        let packetBytes = allNine.flatMap { $0 }

        XCTAssertEqual(MIDIMessageDecoder.splitMessages(packetBytes), allNine)
    }

    func testSplitsMixedMessageLengths() {
        let noteOn: [UInt8] = [0x90, 24, 127]        // 3 bytes
        let programChange: [UInt8] = [0xC0, 5]        // 2 bytes
        let pitchBend: [UInt8] = [0xE0, 0x00, 0x40]   // 3 bytes

        let messages = MIDIMessageDecoder.splitMessages(noteOn + programChange + pitchBend)

        XCTAssertEqual(messages, [noteOn, programChange, pitchBend])
    }

    func testSplitsSysExAmongOtherMessages() {
        let before: [UInt8] = [0x90, 24, 127]
        let sysEx = LaunchpadXProtocol.programmerModeMessage(enabled: true)
        let after: [UInt8] = [0xE0, 0x00, 0x40]

        let messages = MIDIMessageDecoder.splitMessages(before + sysEx + after)

        XCTAssertEqual(messages, [before, sysEx, after])
    }

    func testSplitEmptyBytesReturnsNoMessages() {
        XCTAssertEqual(MIDIMessageDecoder.splitMessages([]), [])
    }

    func testSplitSkipsLeadingStrayDataByte() {
        // A byte below 0x80 with no preceding status shouldn't happen in a well-formed
        // packet, but must not be misread as a status byte if it does.
        let strayByte: UInt8 = 0x40
        let noteOn: [UInt8] = [0x90, 24, 127]

        XCTAssertEqual(MIDIMessageDecoder.splitMessages([strayByte] + noteOn), [noteOn])
    }

    func testSplitTruncatedTrailingMessageDoesNotOverread() {
        // A 3-byte message with only 2 bytes actually present (e.g. a packet cut short)
        // must clamp to what's there, not read past the end of the array.
        let truncated: [UInt8] = [0x90, 24]
        XCTAssertEqual(MIDIMessageDecoder.splitMessages(truncated), [truncated])
    }

    func testSplitSysExWithoutTerminatorConsumesToEnd() {
        let untermindated: [UInt8] = [0xF0, 0x00, 0x20, 0x29]
        XCTAssertEqual(MIDIMessageDecoder.splitMessages(untermindated), [untermindated])
    }

    func testSplitRealTimeBytesAreSingleByteMessages() {
        // 0xF8 (clock) can legitimately appear interleaved with other traffic.
        let clock: [UInt8] = [0xF8]
        let noteOn: [UInt8] = [0x90, 24, 127]
        XCTAssertEqual(MIDIMessageDecoder.splitMessages(clock + noteOn + clock), [clock, noteOn, clock])
    }
}
