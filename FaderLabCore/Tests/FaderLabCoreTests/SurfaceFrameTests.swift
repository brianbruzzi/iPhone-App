import XCTest
@testable import FaderLabCore

final class SurfaceFrameTests: XCTestCase {

    func testAllOffShape() {
        let frame = SurfaceFrame.allOff
        XCTAssertEqual(frame.buttons.count, XTouchSurfaceProtocol.animatableButtonNotes.count)
        XCTAssertEqual(frame.rings.count, XTouchSurfaceProtocol.stripCount)
        XCTAssertEqual(frame.scribbleColors.count, XTouchSurfaceProtocol.stripCount)
        XCTAssertEqual(frame.scribbleTexts.count, XTouchSurfaceProtocol.stripCount)

        XCTAssertTrue(frame.buttons.allSatisfy { $0 == .off })
        XCTAssertTrue(frame.rings.allSatisfy { $0 == .off })
        XCTAssertTrue(frame.scribbleColors.allSatisfy { $0 == .black })
        XCTAssertTrue(frame.scribbleTexts.allSatisfy { $0 == .blank })
    }

    func testButtonNoteSubscriptGetSet() {
        var frame = SurfaceFrame.allOff
        frame[buttonNote: 24] = .solid // SELECT 1
        XCTAssertEqual(frame[buttonNote: 24], .solid)
        // Unrelated note untouched.
        XCTAssertEqual(frame[buttonNote: 25], .off)
    }

    func testButtonNoteSubscriptIgnoresUnknownNote() {
        var frame = SurfaceFrame.allOff
        frame[buttonNote: 200] = .solid // not in animatableButtonNotes — should be a no-op
        XCTAssertEqual(frame[buttonNote: 200], .off)
        XCTAssertTrue(frame.buttons.allSatisfy { $0 == .off }, "writing an unknown note must not corrupt the array")
    }

    func testFillZoneTouchesOnlyThatZone() {
        var frame = SurfaceFrame.allOff
        frame.fill(.select, with: .solid)

        for note in XTouchSurfaceProtocol.ButtonZone.select.notes {
            XCTAssertEqual(frame[buttonNote: note], .solid)
        }
        for note in XTouchSurfaceProtocol.ButtonZone.rec.notes {
            XCTAssertEqual(frame[buttonNote: note], .off)
        }
    }
}
