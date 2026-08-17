import XCTest
@testable import FaderLabCore

final class LaunchpadXProtocolTests: XCTestCase {

    // MARK: - SysEx header / programmer mode

    func testSysExHeaderBytes() {
        XCTAssertEqual(LaunchpadXProtocol.sysExHeader, [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0C])
    }

    func testProgrammerModeEnableMessage() {
        XCTAssertEqual(
            LaunchpadXProtocol.programmerModeMessage(enabled: true),
            [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0C, 0x0E, 0x01, 0xF7]
        )
    }

    func testProgrammerModeDisableMessage() {
        XCTAssertEqual(
            LaunchpadXProtocol.programmerModeMessage(enabled: false),
            [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0C, 0x0E, 0x00, 0xF7]
        )
    }

    // MARK: - Grid <-> note mapping

    func testCornerNoteNumbers() {
        // Bottom-left = note 11; tens digit increases bottom->top, ones digit left->right.
        XCTAssertEqual(LaunchpadXProtocol.note(x: 0, y: 7), 11) // bottom-left
        XCTAssertEqual(LaunchpadXProtocol.note(x: 7, y: 7), 18) // bottom-right
        XCTAssertEqual(LaunchpadXProtocol.note(x: 0, y: 0), 81) // top-left
        XCTAssertEqual(LaunchpadXProtocol.note(x: 7, y: 0), 88) // top-right
    }

    func testNoteXYRoundTrip() {
        for y in 0..<8 {
            for x in 0..<8 {
                let note = LaunchpadXProtocol.note(x: x, y: y)
                let roundTripped = LaunchpadXProtocol.xy(fromNote: note)
                XCTAssertEqual(roundTripped?.x, x, "x mismatch for note \(note)")
                XCTAssertEqual(roundTripped?.y, y, "y mismatch for note \(note)")
            }
        }
    }

    func testXYFromNoteRejectsOutsideGrid() {
        // Notes ending in 9 or 0 are the scene-launch column / top-row function buttons.
        XCTAssertNil(LaunchpadXProtocol.xy(fromNote: 19))
        XCTAssertNil(LaunchpadXProtocol.xy(fromNote: 90))
        XCTAssertNil(LaunchpadXProtocol.xy(fromNote: 9))
        XCTAssertNil(LaunchpadXProtocol.xy(fromNote: 99))
    }

    // MARK: - RGB frame encoding

    func testFrameMessageLength() {
        let message = LaunchpadXProtocol.frameMessage(.allBlack)
        // header(6) + command(1) + 64 pads * 5 bytes + terminator(1)
        XCTAssertEqual(message.count, 6 + 1 + 64 * 5 + 1)
    }

    func testFrameMessageStructure() {
        var grid = PixelGrid.allBlack
        grid[0, 0] = RGBColor(r: 255, g: 0, b: 0) // top-left pad, pure red

        let message = LaunchpadXProtocol.frameMessage(grid)

        XCTAssertEqual(Array(message[0..<6]), LaunchpadXProtocol.sysExHeader)
        XCTAssertEqual(message[6], 0x03) // RGB lighting command

        // First colourspec entry: type=0x03, note=81 (top-left), scaled red = 127, g=0, b=0.
        XCTAssertEqual(Array(message[7..<12]), [0x03, 81, 127, 0, 0])

        // Second colourspec entry: the next pad in iteration order (x=1, y=0), still black.
        XCTAssertEqual(Array(message[12..<17]), [0x03, 82, 0, 0, 0])

        XCTAssertEqual(message.last, 0xF7)
    }

    func testClearAllMessageMatchesAllBlackFrame() {
        XCTAssertEqual(LaunchpadXProtocol.clearAllMessage(), LaunchpadXProtocol.frameMessage(.allBlack))
    }

    func testClearAllMessageIsAllZeroColour() {
        let message = LaunchpadXProtocol.clearAllMessage()
        // Every colourspec entry's R/G/B bytes (offsets 2,3,4 within each 5-byte group) are 0.
        let colourSpecs = stride(from: 7, to: message.count - 1, by: 5)
        for offset in colourSpecs {
            XCTAssertEqual(message[offset], 0x03) // type
            XCTAssertEqual(message[offset + 2], 0) // R
            XCTAssertEqual(message[offset + 3], 0) // G
            XCTAssertEqual(message[offset + 4], 0) // B
        }
    }
}
