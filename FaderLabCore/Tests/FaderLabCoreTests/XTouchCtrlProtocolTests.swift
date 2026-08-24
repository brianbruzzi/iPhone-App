import XCTest
@testable import FaderLabCore

final class XTouchCtrlProtocolTests: XCTestCase {

    // MARK: - Fader encoding (Behringer doc: CC 70-77, master CC 78, channel 1)

    func testFaderBytesFirstFaderFullUp() {
        XCTAssertEqual(XTouchCtrlProtocol.faderBytes(fader: 0, value7: 127), [0xB0, 70, 127])
    }

    func testFaderBytesFirstFaderFullDown() {
        XCTAssertEqual(XTouchCtrlProtocol.faderBytes(fader: 0, value7: 0), [0xB0, 70, 0])
    }

    func testFaderBytesCCNumberPerFader() {
        for fader in 0..<XTouchCtrlProtocol.faderCount {
            let bytes = XTouchCtrlProtocol.faderBytes(fader: fader, value7: 64)
            XCTAssertEqual(bytes[0], 0xB0, "Ctrl mode faders are always on channel 1")
            XCTAssertEqual(bytes[1], UInt8(70 + fader), "fader \(fader) should be CC \(70 + fader)")
        }
    }

    func testMasterFaderIsCC78() {
        let bytes = XTouchCtrlProtocol.faderBytes(fader: XTouchCtrlProtocol.masterFaderIndex, value7: 127)
        XCTAssertEqual(bytes, [0xB0, 78, 127])
    }

    func testFaderValueClamped() {
        XCTAssertEqual(XTouchCtrlProtocol.faderBytes(fader: 0, value7: -50), [0xB0, 70, 0])
        XCTAssertEqual(XTouchCtrlProtocol.faderBytes(fader: 0, value7: 9999), [0xB0, 70, 127])
    }

    func testFaderUnitValueOverload() {
        XCTAssertEqual(XTouchCtrlProtocol.faderBytes(fader: 3, unitValue: 1.0), [0xB0, 73, 127])
        XCTAssertEqual(XTouchCtrlProtocol.faderBytes(fader: 3, unitValue: 0.0), [0xB0, 73, 0])
    }

    // MARK: - Fader decoding

    func testDecodeFaderRoundTrip() {
        for fader in [0, 4, 8] {
            for value in [0, 1, 64, 126, 127] {
                let bytes = XTouchCtrlProtocol.faderBytes(fader: fader, value7: value)
                let decoded = XTouchCtrlProtocol.decodeFader(bytes)
                XCTAssertEqual(decoded, XTouchCtrlProtocol.FaderPositionReport(fader: fader, value7: value))
            }
        }
    }

    func testDecodeFaderRejectsOutOfRangeCC() {
        XCTAssertNil(XTouchCtrlProtocol.decodeFader([0xB0, 69, 64])) // one below fader 1
        XCTAssertNil(XTouchCtrlProtocol.decodeFader([0xB0, 79, 64])) // one above master
    }

    func testDecodeFaderRejectsWrongChannel() {
        XCTAssertNil(XTouchCtrlProtocol.decodeFader([0xB1, 70, 64]))
    }

    func testDecodeFaderRejectsPitchBend() {
        // An MC-mode fader message must not be mistaken for a Ctrl-mode one.
        XCTAssertNil(XTouchCtrlProtocol.decodeFader([0xE0, 0x00, 0x40]))
    }

    // MARK: - Touch sense (notes 110-117, master 118)

    func testDecodeTouchFirstFader() {
        let event = XTouchCtrlProtocol.decodeTouch([0x90, 110, 127])
        XCTAssertEqual(event, XTouchProtocol.FaderTouchEvent(fader: 0, touched: true))
    }

    func testDecodeTouchMasterFader() {
        let event = XTouchCtrlProtocol.decodeTouch([0x90, 118, 127])
        XCTAssertEqual(event, XTouchProtocol.FaderTouchEvent(fader: 8, touched: true))
    }

    func testDecodeTouchRelease() {
        XCTAssertEqual(
            XTouchCtrlProtocol.decodeTouch([0x90, 110, 0]),
            XTouchProtocol.FaderTouchEvent(fader: 0, touched: false)
        )
        XCTAssertEqual(
            XTouchCtrlProtocol.decodeTouch([0x80, 110, 0]),
            XTouchProtocol.FaderTouchEvent(fader: 0, touched: false)
        )
    }

    func testTouchRangesPartiallyOverlapWithMCMode() {
        // MC touch is notes 104-112, Ctrl touch is 110-118. The ends are exclusive to one
        // mode each, but 110-112 genuinely belong to both — which is why
        // MIDIMessageDecoder.inferMode refuses to guess a mode from those notes.
        XCTAssertNil(XTouchCtrlProtocol.decodeTouch([0x90, 104, 127]), "104 is MC-only")
        XCTAssertNil(XTouchProtocol.decodeTouch([0x90, 118, 127]), "118 is Ctrl-only")

        XCTAssertNotNil(XTouchProtocol.decodeTouch([0x90, 110, 127]), "110 is in both ranges")
        XCTAssertNotNil(XTouchCtrlProtocol.decodeTouch([0x90, 110, 127]), "110 is in both ranges")
    }

    // MARK: - Button LEDs (vel 0-63 off, 64 flash, 65-127 on)

    func testButtonLEDVelocities() {
        XCTAssertEqual(XTouchCtrlProtocol.buttonLEDBytes(note: 24, state: .off), [0x90, 24, 0])
        XCTAssertEqual(XTouchCtrlProtocol.buttonLEDBytes(note: 24, state: .flash), [0x90, 24, 64])
        XCTAssertEqual(XTouchCtrlProtocol.buttonLEDBytes(note: 24, state: .on), [0x90, 24, 127])
    }

    // MARK: - Unit conversion

    func testUnitConversionBoundaries() {
        XCTAssertEqual(XTouchCtrlProtocol.value7(fromUnit: 0), 0)
        XCTAssertEqual(XTouchCtrlProtocol.value7(fromUnit: 1), 127)
        XCTAssertEqual(XTouchCtrlProtocol.value7(fromUnit: -3), 0)
        XCTAssertEqual(XTouchCtrlProtocol.value7(fromUnit: 3), 127)
        XCTAssertEqual(XTouchCtrlProtocol.unit(fromValue7: 0), 0.0)
        XCTAssertEqual(XTouchCtrlProtocol.unit(fromValue7: 127), 1.0)
    }
}
