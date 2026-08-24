import XCTest
@testable import FaderLabCore

final class XTouchSurfaceProtocolTests: XCTestCase {

    // MARK: - Button LEDs

    func testButtonLEDByteValues() {
        XCTAssertEqual(XTouchSurfaceProtocol.buttonLEDBytes(note: 24, state: .off), [0x90, 24, 0x00])
        XCTAssertEqual(XTouchSurfaceProtocol.buttonLEDBytes(note: 24, state: .blink), [0x90, 24, 0x01])
        XCTAssertEqual(XTouchSurfaceProtocol.buttonLEDBytes(note: 24, state: .solid), [0x90, 24, 0x7F])
    }

    func testButtonZoneNoteRanges() {
        XCTAssertEqual(XTouchSurfaceProtocol.ButtonZone.rec.notes, Array(0...7))
        XCTAssertEqual(XTouchSurfaceProtocol.ButtonZone.solo.notes, Array(8...15))
        XCTAssertEqual(XTouchSurfaceProtocol.ButtonZone.mute.notes, Array(16...23))
        XCTAssertEqual(XTouchSurfaceProtocol.ButtonZone.select.notes, Array(24...31))
        XCTAssertEqual(XTouchSurfaceProtocol.ButtonZone.vpotPress.notes, Array(32...39))
        XCTAssertEqual(XTouchSurfaceProtocol.ButtonZone.function.notes, Array(54...61))
        XCTAssertEqual(XTouchSurfaceProtocol.ButtonZone.transport.notes, Array(91...95))
        XCTAssertEqual(XTouchSurfaceProtocol.ButtonZone.assign.notes, Array(40...45))
        XCTAssertEqual(XTouchSurfaceProtocol.ButtonZone.bankNav.notes, Array(46...49))
        XCTAssertEqual(XTouchSurfaceProtocol.ButtonZone.miscToggles.notes, Array(50...51))
        XCTAssertEqual(XTouchSurfaceProtocol.ButtonZone.globalView.notes, Array(62...69))
        XCTAssertEqual(XTouchSurfaceProtocol.ButtonZone.modifier.notes, Array(70...73))
        XCTAssertEqual(XTouchSurfaceProtocol.ButtonZone.automation.notes, Array(74...79))
        XCTAssertEqual(XTouchSurfaceProtocol.ButtonZone.utility.notes, Array(80...90))
        XCTAssertEqual(XTouchSurfaceProtocol.ButtonZone.cursor.notes, Array(96...101))
        XCTAssertEqual(XTouchSurfaceProtocol.ButtonZone.userSwitch.notes, Array(102...103))
        XCTAssertEqual(XTouchSurfaceProtocol.ButtonZone.indicator.notes, Array(113...115))
    }

    func testAnimatableButtonNotesIsSortedUniqueUnionOfZones() {
        let notes = XTouchSurfaceProtocol.animatableButtonNotes
        XCTAssertEqual(notes.count, 105)
        XCTAssertEqual(notes, notes.sorted())
        XCTAssertEqual(Set(notes).count, notes.count, "must be unique — zones must not overlap")
    }

    func testButtonIndexRoundTripsWithAnimatableButtonNotes() {
        for (index, note) in XTouchSurfaceProtocol.animatableButtonNotes.enumerated() {
            XCTAssertEqual(XTouchSurfaceProtocol.buttonIndex(forNote: note), index)
        }
    }

    func testButtonIndexReturnsNilForUnanimatedNote() {
        // 52/53 (Name/Value, SMPTE/Beats) are confirmed to have no LED at all, so they're
        // deliberately excluded from `miscToggles`. 104...112 are the fader touch-sense
        // notes, not LEDs, and are never part of any ButtonZone.
        XCTAssertNil(XTouchSurfaceProtocol.buttonIndex(forNote: 52))
        XCTAssertNil(XTouchSurfaceProtocol.buttonIndex(forNote: 53))
        XCTAssertNil(XTouchSurfaceProtocol.buttonIndex(forNote: 104))
        XCTAssertNil(XTouchSurfaceProtocol.buttonIndex(forNote: 112))
        XCTAssertNil(XTouchSurfaceProtocol.buttonIndex(forNote: 116))
        XCTAssertNil(XTouchSurfaceProtocol.buttonIndex(forNote: 255))
    }

    // MARK: - Section split (channel strips vs. right-hand cluster)

    func testSectionsPartitionAnimatableButtonNotes() {
        let right = Set(XTouchSurfaceProtocol.rightSectionButtonNotes)
        let strip = Set(XTouchSurfaceProtocol.channelStripZones.flatMap { $0.notes })

        XCTAssertTrue(right.isDisjoint(with: strip), "a note must belong to exactly one section")
        XCTAssertEqual(right.union(strip), Set(XTouchSurfaceProtocol.animatableButtonNotes))
        XCTAssertEqual(strip.count, 40, "5 channel-strip zones x 8 notes")
        XCTAssertEqual(right.count, 65, "105 animatable notes - 40 channel-strip notes")
    }

    /// Guards against a future `ButtonZone` case being added and silently classified into
    /// neither section — which would leave it permanently dark once the right-hand splice
    /// starts overwriting everything it does cover.
    func testEveryZoneBelongsToExactlyOneSection() {
        let right = Set(XTouchSurfaceProtocol.rightSectionButtonNotes)
        let strip = Set(XTouchSurfaceProtocol.channelStripZones.flatMap { $0.notes })

        for zone in XTouchSurfaceProtocol.ButtonZone.allCases {
            let notes = Set(zone.notes)
            let inRight = notes.isSubset(of: right)
            let inStrip = notes.isSubset(of: strip)
            XCTAssertTrue(inRight != inStrip, "\(zone) must belong to exactly one section, in full")
        }
    }

    func testRightSectionButtonNotesAreSortedAndAllAtLeast40() {
        let notes = XTouchSurfaceProtocol.rightSectionButtonNotes
        XCTAssertEqual(notes, notes.sorted())
        XCTAssertEqual(Set(notes).count, notes.count)
        XCTAssertEqual(notes.first, 40)
        XCTAssertTrue(notes.allSatisfy { $0 >= 40 })
    }

    func testRightSectionButtonIndicesMatchTheirNotes() {
        XCTAssertEqual(
            XTouchSurfaceProtocol.rightSectionButtonIndices,
            XTouchSurfaceProtocol.rightSectionButtonNotes.map { XTouchSurfaceProtocol.buttonIndex(forNote: $0) ?? -1 }
        )
        // The channel strips occupy notes 0...39, which are also frame indices 0...39 (the
        // note range is contiguous and `animatableButtonNotes` is sorted), so the
        // right-hand section is exactly the tail of the buttons array.
        XCTAssertEqual(XTouchSurfaceProtocol.rightSectionButtonIndices, Array(40..<105))
    }

    // MARK: - Encoder LED rings

    func testRingValueByteEncoding() {
        XCTAssertEqual(XTouchSurfaceProtocol.ringValueByte(.off), 0x00)
        XCTAssertEqual(XTouchSurfaceProtocol.ringValueByte(.init(mode: .dot, position: 5)), 0x05)
        XCTAssertEqual(XTouchSurfaceProtocol.ringValueByte(.init(mode: .boostCut, position: 11)), 0x1B)
        XCTAssertEqual(XTouchSurfaceProtocol.ringValueByte(.init(mode: .wrap, position: 11)), 0x2B)
        XCTAssertEqual(XTouchSurfaceProtocol.ringValueByte(.init(mode: .spread, position: 11, centerLED: true)), 0x7B)
    }

    func testRingValueByteClampsPosition() {
        XCTAssertEqual(XTouchSurfaceProtocol.ringValueByte(.init(mode: .dot, position: 12)), 0x0B)
        XCTAssertEqual(XTouchSurfaceProtocol.ringValueByte(.init(mode: .dot, position: -1)), 0x00)
    }

    func testRingBytesMessage() {
        XCTAssertEqual(XTouchSurfaceProtocol.ringBytes(strip: 0, display: .off), [0xB0, 48, 0x00])
        XCTAssertEqual(
            XTouchSurfaceProtocol.ringBytes(strip: 7, display: .init(mode: .wrap, position: 11)),
            [0xB0, 55, 0x2B]
        )
    }

    // MARK: - Scribble text

    func testScribbleTextOffsets() {
        // strip 0 upper = 0, strip 3 lower = 56 + 3*7 = 77
        let upperMessage = XTouchSurfaceProtocol.scribbleTextMessage(strip: 0, row: .upper, text: "A")
        XCTAssertEqual(upperMessage[6], 0)

        let lowerMessage = XTouchSurfaceProtocol.scribbleTextMessage(strip: 3, row: .lower, text: "A")
        XCTAssertEqual(lowerMessage[6], 77)
    }

    func testScribbleTextExactSevenBytePayload() {
        let message = XTouchSurfaceProtocol.scribbleTextMessage(strip: 0, row: .upper, text: "HELLO")
        // header(5) + command(1) + offset(1) + 7 chars + terminator(1)
        XCTAssertEqual(message.count, 5 + 1 + 1 + 7 + 1)
        XCTAssertEqual(Array(message[7..<14]), [0x48, 0x45, 0x4C, 0x4C, 0x4F, 0x20, 0x20]) // "HELLO  "
        XCTAssertEqual(message.last, 0xF7)
    }

    func testScribbleTextPadsShortStrings() {
        let message = XTouchSurfaceProtocol.scribbleTextMessage(strip: 0, row: .upper, text: "AB")
        XCTAssertEqual(Array(message[7..<14]), [0x41, 0x42, 0x20, 0x20, 0x20, 0x20, 0x20])
    }

    func testScribbleTextTruncatesLongStrings() {
        let message = XTouchSurfaceProtocol.scribbleTextMessage(strip: 0, row: .upper, text: "ABCDEFGHIJ")
        XCTAssertEqual(Array(message[7..<14]), [0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47]) // "ABCDEFG"
    }

    func testScribbleTextReplacesNonPrintableWithSpace() {
        let message = XTouchSurfaceProtocol.scribbleTextMessage(strip: 0, row: .upper, text: "A\tB\u{1F600}C")
        // "A", tab->space, "B", emoji->space, "C", pad x2
        XCTAssertEqual(Array(message[7..<14]), [0x41, 0x20, 0x42, 0x20, 0x43, 0x20, 0x20])
    }

    func testScribbleTextEmptyStringIsAllSpaces() {
        let message = XTouchSurfaceProtocol.scribbleTextMessage(strip: 0, row: .upper, text: "")
        XCTAssertEqual(Array(message[7..<14]), Array(repeating: 0x20, count: 7))
    }

    // MARK: - Scribble colors

    func testScribbleColorsMessageLayout() {
        let colors: [XTouchSurfaceProtocol.ScribbleColor] = [.black, .red, .green, .yellow, .blue, .magenta, .cyan, .white]
        let message = XTouchSurfaceProtocol.scribbleColorsMessage(colors)

        XCTAssertEqual(Array(message[0..<5]), XTouchSurfaceProtocol.scribbleSysExHeader)
        XCTAssertEqual(message[5], 0x72)
        XCTAssertEqual(Array(message[6..<14]), [0, 1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(message.last, 0xF7)
    }

    // MARK: - Forbidden command safety net

    func testForbiddenCommandConstantIs0x04() {
        XCTAssertEqual(XTouchSurfaceProtocol.forbiddenSysExCommand, 0x04)
    }

    func testNoEncoderEmitsForbiddenCommand04() {
        let messages: [[UInt8]] = [
            XTouchSurfaceProtocol.scribbleTextMessage(strip: 0, row: .upper, text: "TEST"),
            XTouchSurfaceProtocol.scribbleTextMessage(strip: 7, row: .lower, text: "TEST"),
            XTouchSurfaceProtocol.scribbleColorsMessage(Array(repeating: .white, count: 8)),
            XTouchSurfaceProtocol.vuEnableMessage(strip: 0, enabled: true),
            XTouchSurfaceProtocol.vuEnableMessage(strip: 0, enabled: false),
        ]
        for message in messages {
            guard message.first == 0xF0 else { continue } // only SysEx messages carry a command byte
            let commandByte = message[XTouchSurfaceProtocol.scribbleSysExHeader.count]
            XCTAssertNotEqual(
                commandByte, XTouchSurfaceProtocol.forbiddenSysExCommand,
                "message \(MIDIMessageDecoder.hexString(message)) must never use the forbidden command byte"
            )
        }
    }

    // MARK: - VU meters

    func testVULevelBytesPacking() {
        // strip 3, level 9 -> D0 39
        XCTAssertEqual(XTouchSurfaceProtocol.vuLevelBytes(strip: 3, level: 9), [0xD0, 0x39])
    }

    func testVULevelBytesClamps() {
        XCTAssertEqual(XTouchSurfaceProtocol.vuLevelBytes(strip: 0, level: 999), [0xD0, 0x0D])
        XCTAssertEqual(XTouchSurfaceProtocol.vuLevelBytes(strip: 0, level: -5), [0xD0, 0x00])
    }

    func testVULevelNeverReachesTheOverloadLatches() {
        // 0x0E/0x0F are set/clear-overload commands, not levels — a value that ran past
        // 0x0D would latch a clip indicator that then needs an explicit clear to release.
        for unit in [-1.0, 0.0, 0.5, 1.0, 2.0, Double.nan, Double.infinity] {
            let level = XTouchSurfaceProtocol.vuLevel(forUnitValue: unit)
            XCTAssertLessThanOrEqual(level, XTouchSurfaceProtocol.vuMaxLevel)
            XCTAssertGreaterThanOrEqual(level, 0)
        }
    }

    func testVULevelMapsUnitRangeAcrossTheFullScale() {
        XCTAssertEqual(XTouchSurfaceProtocol.vuLevel(forUnitValue: 0), 0)
        XCTAssertEqual(XTouchSurfaceProtocol.vuLevel(forUnitValue: 1), XTouchSurfaceProtocol.vuMaxLevel)
        XCTAssertEqual(XTouchSurfaceProtocol.vuLevel(forUnitValue: 0.5), 7) // round(0.5 * 13)
    }

    // MARK: - 7-segment display

    func testDisplayDigitValueEncodesAsLowSixBitsOfASCII() {
        XCTAssertEqual(XTouchSurfaceProtocol.displayDigitValue(for: "0"), 0x30)
        XCTAssertEqual(XTouchSurfaceProtocol.displayDigitValue(for: "9"), 0x39)
        XCTAssertEqual(XTouchSurfaceProtocol.displayDigitValue(for: "A"), 0x01)
        XCTAssertEqual(XTouchSurfaceProtocol.displayDigitValue(for: "Z"), 0x1A)
        XCTAssertEqual(XTouchSurfaceProtocol.displayDigitValue(for: " "), 0x20)
    }

    func testDisplayDigitValueUppercasesAndFallsBackToSpace() {
        XCTAssertEqual(
            XTouchSurfaceProtocol.displayDigitValue(for: "a"),
            XTouchSurfaceProtocol.displayDigitValue(for: "A")
        )
        // Outside the supported 0x20...0x5F window (lowercase already handled above).
        XCTAssertEqual(XTouchSurfaceProtocol.displayDigitValue(for: "\u{7F}"), 0x20)
        XCTAssertEqual(XTouchSurfaceProtocol.displayDigitValue(for: "é"), 0x20)
        XCTAssertEqual(XTouchSurfaceProtocol.displayDigitValue(for: "\t"), 0x20)
    }

    func testDisplayDotSetsBitSixWithoutDisturbingTheCharacter() {
        let plain = XTouchSurfaceProtocol.displayDigitValue(for: "5")
        let dotted = XTouchSurfaceProtocol.displayDigitValue(for: "5", dot: true)
        XCTAssertEqual(dotted, plain | 0x40)
        XCTAssertEqual(dotted & 0x3F, plain)
    }

    /// CC 0x40 is the *rightmost* digit, so reading-order position 0 must land on the
    /// highest CC. Getting this backwards would silently render every message mirrored.
    func testDisplayDigitPositionZeroIsLeftmostAndMapsToHighestCC() {
        XCTAssertEqual(
            XTouchSurfaceProtocol.displayDigitBytes(position: 0, character: "A"),
            [0xB0, 0x4B, 0x01]
        )
        XCTAssertEqual(
            XTouchSurfaceProtocol.displayDigitBytes(position: 11, character: "A"),
            [0xB0, 0x40, 0x01]
        )
    }

    func testDisplayTextIsLeftAlignedAndSpacePadded() {
        let messages = XTouchSurfaceProtocol.displayTextMessages("HI")
        XCTAssertEqual(messages.count, XTouchSurfaceProtocol.displayDigitCount)

        // "H" leftmost (CC 0x4B), "I" next (CC 0x4A), the rest blanked.
        XCTAssertEqual(messages[0], [0xB0, 0x4B, XTouchSurfaceProtocol.displayDigitValue(for: "H")])
        XCTAssertEqual(messages[1], [0xB0, 0x4A, XTouchSurfaceProtocol.displayDigitValue(for: "I")])
        for message in messages.dropFirst(2) {
            XCTAssertEqual(message[2], 0x20, "unused digits must be blanked, not left stale")
        }
    }

    func testDisplayTextTruncatesPastTwelveCharacters() {
        let messages = XTouchSurfaceProtocol.displayTextMessages("ABCDEFGHIJKLMNOP")
        XCTAssertEqual(messages.count, XTouchSurfaceProtocol.displayDigitCount)
        XCTAssertEqual(messages[0][2], XTouchSurfaceProtocol.displayDigitValue(for: "A"))
        XCTAssertEqual(messages[11][2], XTouchSurfaceProtocol.displayDigitValue(for: "L"))
    }

    /// The exact message this was built for — 10 characters across the timecode block.
    func testDisplayTextRendersSmartStopInReadingOrder() {
        let messages = XTouchSurfaceProtocol.displayTextMessages("SMART STOP")
        let byCC = Dictionary(uniqueKeysWithValues: messages.map { ($0[1], $0[2]) })

        for (offset, character) in Array("SMART STOP").enumerated() {
            let cc = UInt8(0x4B - offset)
            XCTAssertEqual(
                byCC[cc], XTouchSurfaceProtocol.displayDigitValue(for: character),
                "character \(offset) ('\(character)') landed on the wrong digit"
            )
        }
    }

    func testDisplayMessagesAreAllControlChangeNeverSysEx() {
        // Cheap insurance that the display path can never wander into SysEx territory,
        // where the forbidden 0x04 command lives.
        for message in XTouchSurfaceProtocol.displayTextMessages("TEST 12345") {
            XCTAssertEqual(message.count, 3)
            XCTAssertEqual(message[0], 0xB0)
            XCTAssertTrue((0x40...0x4B).contains(message[1]))
            XCTAssertLessThan(message[2], 0x80, "value byte must stay 7-bit")
        }
    }

    func testVUEnableMessage() {
        XCTAssertEqual(
            XTouchSurfaceProtocol.vuEnableMessage(strip: 2, enabled: true),
            XTouchSurfaceProtocol.scribbleSysExHeader + [0x20, 2, 0x01, 0xF7]
        )
        XCTAssertEqual(
            XTouchSurfaceProtocol.vuEnableMessage(strip: 2, enabled: false),
            XTouchSurfaceProtocol.scribbleSysExHeader + [0x20, 2, 0x00, 0xF7]
        )
    }
}
