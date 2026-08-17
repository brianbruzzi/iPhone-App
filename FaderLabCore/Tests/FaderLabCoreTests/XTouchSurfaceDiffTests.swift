import XCTest
@testable import FaderLabCore

final class XTouchSurfaceDiffTests: XCTestCase {

    func testNilOldProducesFullRepaint() {
        let messages = XTouchSurfaceDiff.messages(from: nil, to: .allOff)
        // 104 buttons + 8 rings + 1 color message + 16 text cells (8 strips x 2 rows)
        XCTAssertEqual(messages.count, 104 + 8 + 1 + 16)
    }

    func testFullRepaintOrderIsButtonsThenRingsThenColorsThenTexts() {
        let messages = XTouchSurfaceDiff.messages(from: nil, to: .allOff)

        let buttonCount = XTouchSurfaceProtocol.animatableButtonNotes.count
        for message in messages[0..<buttonCount] {
            XCTAssertEqual(message[0], 0x90, "expected a button Note On message")
        }
        for message in messages[buttonCount..<(buttonCount + 8)] {
            XCTAssertEqual(message[0], 0xB0, "expected an encoder ring CC message")
        }
        let colorMessage = messages[buttonCount + 8]
        XCTAssertEqual(colorMessage[5], 0x72, "expected the scribble color SysEx command")
        for message in messages[(buttonCount + 9)...] {
            XCTAssertEqual(message[5], 0x12, "expected a scribble text SysEx command")
        }
    }

    func testEqualFramesProduceNoMessages() {
        XCTAssertEqual(XTouchSurfaceDiff.messages(from: .allOff, to: .allOff), [])
    }

    func testSingleButtonChangeProducesOneMessage() {
        var new = SurfaceFrame.allOff
        new[buttonNote: 24] = .solid

        let messages = XTouchSurfaceDiff.messages(from: .allOff, to: new)

        XCTAssertEqual(messages, [XTouchSurfaceProtocol.buttonLEDBytes(note: 24, state: .solid)])
    }

    func testSingleRingChangeProducesOneMessage() {
        var new = SurfaceFrame.allOff
        new.rings[3] = .init(mode: .wrap, position: 6)

        let messages = XTouchSurfaceDiff.messages(from: .allOff, to: new)

        XCTAssertEqual(messages, [XTouchSurfaceProtocol.ringBytes(strip: 3, display: .init(mode: .wrap, position: 6))])
    }

    func testAnyScribbleColorChangeProducesExactlyOneColorMessage() {
        var new = SurfaceFrame.allOff
        new.scribbleColors[0] = .red
        new.scribbleColors[5] = .blue // two strips changed, still one message on the wire

        let messages = XTouchSurfaceDiff.messages(from: .allOff, to: new)

        XCTAssertEqual(messages, [XTouchSurfaceProtocol.scribbleColorsMessage(new.scribbleColors)])
    }

    func testSingleTextCellChangeProducesOneMessage() {
        var new = SurfaceFrame.allOff
        new.scribbleTexts[2] = ScribbleText(upper: "HI", lower: "")

        let messages = XTouchSurfaceDiff.messages(from: .allOff, to: new)

        XCTAssertEqual(messages, [XTouchSurfaceProtocol.scribbleTextMessage(strip: 2, row: .upper, text: "HI")])
    }

    func testUnchangedTextIsNeverResent() {
        var old = SurfaceFrame.allOff
        old.scribbleTexts[0] = ScribbleText(upper: "SAME", lower: "SAME")
        var new = old
        new.buttons[0] = .solid // change something unrelated

        let messages = XTouchSurfaceDiff.messages(from: old, to: new)

        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages, [XTouchSurfaceProtocol.buttonLEDBytes(note: XTouchSurfaceProtocol.animatableButtonNotes[0], state: .solid)])
    }

    func testBothTextRowsChangingProducesTwoMessages() {
        var new = SurfaceFrame.allOff
        new.scribbleTexts[4] = ScribbleText(upper: "TOP", lower: "BOTTOM")

        let messages = XTouchSurfaceDiff.messages(from: .allOff, to: new)

        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue(messages.contains(XTouchSurfaceProtocol.scribbleTextMessage(strip: 4, row: .upper, text: "TOP")))
        XCTAssertTrue(messages.contains(XTouchSurfaceProtocol.scribbleTextMessage(strip: 4, row: .lower, text: "BOTTOM")))
    }
}
