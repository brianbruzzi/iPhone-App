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
    }

    func testAnimatableButtonNotesIsSortedUniqueUnionOfZones() {
        let notes = XTouchSurfaceProtocol.animatableButtonNotes
        XCTAssertEqual(notes.count, 53)
        XCTAssertEqual(notes, notes.sorted())
        XCTAssertEqual(Set(notes).count, notes.count, "must be unique — zones must not overlap")
    }

    func testButtonIndexRoundTripsWithAnimatableButtonNotes() {
        for (index, note) in XTouchSurfaceProtocol.animatableButtonNotes.enumerated() {
            XCTAssertEqual(XTouchSurfaceProtocol.buttonIndex(forNote: note), index)
        }
    }

    func testButtonIndexReturnsNilForUnanimatedNote() {
        // Note 40 falls in the gap between vpotPress (32-39) and function (54-61).
        XCTAssertNil(XTouchSurfaceProtocol.buttonIndex(forNote: 40))
        XCTAssertNil(XTouchSurfaceProtocol.buttonIndex(forNote: 255))
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
