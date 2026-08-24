import XCTest
@testable import FaderLabCore

final class XTouchProtocolTests: XCTestCase {

    // MARK: - Pitch bend encoding

    func testPitchBendBytesFullUp() {
        XCTAssertEqual(XTouchProtocol.pitchBendBytes(fader: 0, value14: 16383), [0xE0, 0x7F, 0x7F])
    }

    func testPitchBendBytesFullDown() {
        XCTAssertEqual(XTouchProtocol.pitchBendBytes(fader: 0, value14: 0), [0xE0, 0x00, 0x00])
    }

    func testPitchBendBytesChannelPerFader() {
        for fader in 0..<XTouchProtocol.faderCount {
            let bytes = XTouchProtocol.pitchBendBytes(fader: fader, value14: 0)
            XCTAssertEqual(bytes[0], 0xE0 | UInt8(fader), "fader \(fader) should use channel \(fader)")
        }
    }

    func testMasterFaderIsChannel8() {
        XCTAssertEqual(XTouchProtocol.masterFaderIndex, 8)
        let bytes = XTouchProtocol.pitchBendBytes(fader: 8, value14: 16383)
        XCTAssertEqual(bytes[0], 0xE8)
    }

    func testPitchBendValueClamped() {
        XCTAssertEqual(XTouchProtocol.pitchBendBytes(fader: 0, value14: -100), [0xE0, 0x00, 0x00])
        XCTAssertEqual(XTouchProtocol.pitchBendBytes(fader: 0, value14: 99999), [0xE0, 0x7F, 0x7F])
    }

    func testPitchBendUnitValueOverload() {
        XCTAssertEqual(XTouchProtocol.pitchBendBytes(fader: 2, unitValue: 1.0), [0xE2, 0x7F, 0x7F])
        XCTAssertEqual(XTouchProtocol.pitchBendBytes(fader: 2, unitValue: 0.0), [0xE2, 0x00, 0x00])
    }

    // MARK: - Pitch bend decoding

    func testDecodePitchBendRoundTrip() {
        for fader in [0, 4, 8] {
            for value in [0, 1, 8192, 16382, 16383] {
                let bytes = XTouchProtocol.pitchBendBytes(fader: fader, value14: value)
                let decoded = XTouchProtocol.decodePitchBend(bytes)
                XCTAssertEqual(decoded, XTouchProtocol.FaderPositionReport(fader: fader, value14: value))
            }
        }
    }

    func testDecodePitchBendRejectsWrongLength() {
        XCTAssertNil(XTouchProtocol.decodePitchBend([0xE0, 0x00]))
        XCTAssertNil(XTouchProtocol.decodePitchBend([0xE0, 0x00, 0x00, 0x00]))
    }

    func testDecodePitchBendRejectsNonPitchBendStatus() {
        XCTAssertNil(XTouchProtocol.decodePitchBend([0x90, 0x40, 0x7F])) // note on, not pitch bend
    }

    func testDecodePitchBendRejectsOutOfRangeChannel() {
        // Channel 9 (0xE9) is beyond the 9 faders (indices 0...8).
        XCTAssertNil(XTouchProtocol.decodePitchBend([0xE9, 0x00, 0x00]))
    }

    // MARK: - Touch sense decoding

    func testDecodeTouchOnFirstFader() {
        let event = XTouchProtocol.decodeTouch([0x90, 0x68, 0x7F])
        XCTAssertEqual(event, XTouchProtocol.FaderTouchEvent(fader: 0, touched: true))
    }

    func testDecodeTouchOnMasterFader() {
        let event = XTouchProtocol.decodeTouch([0x90, 0x70, 0x7F])
        XCTAssertEqual(event, XTouchProtocol.FaderTouchEvent(fader: 8, touched: true))
    }

    func testDecodeTouchOffExplicitNoteOff() {
        let event = XTouchProtocol.decodeTouch([0x80, 0x68, 0x00])
        XCTAssertEqual(event, XTouchProtocol.FaderTouchEvent(fader: 0, touched: false))
    }

    func testDecodeTouchOffViaNoteOnVelocityZero() {
        // Common MIDI convention: Note On with velocity 0 is treated as Note Off.
        let event = XTouchProtocol.decodeTouch([0x90, 0x68, 0x00])
        XCTAssertEqual(event, XTouchProtocol.FaderTouchEvent(fader: 0, touched: false))
    }

    func testDecodeTouchRejectsNoteOutsideRange() {
        XCTAssertNil(XTouchProtocol.decodeTouch([0x90, 0x67, 0x7F])) // one below fader 1's note
        XCTAssertNil(XTouchProtocol.decodeTouch([0x90, 0x71, 0x7F])) // one above master's note
    }

    func testDecodeTouchRejectsWrongStatusByte() {
        XCTAssertNil(XTouchProtocol.decodeTouch([0xE0, 0x68, 0x7F])) // pitch bend, not a note message
        XCTAssertNil(XTouchProtocol.decodeTouch([0x91, 0x68, 0x7F])) // channel 2, not channel 1
    }

    // MARK: - Unit <-> 14-bit conversion

    func testUnitToValue14() {
        XCTAssertEqual(XTouchProtocol.value14(fromUnit: 0), 0)
        XCTAssertEqual(XTouchProtocol.value14(fromUnit: 1), 16383)
        XCTAssertEqual(XTouchProtocol.value14(fromUnit: -5), 0) // clamped
        XCTAssertEqual(XTouchProtocol.value14(fromUnit: 5), 16383) // clamped
    }

    func testValue14ToUnit() {
        XCTAssertEqual(XTouchProtocol.unit(fromValue14: 0), 0.0)
        XCTAssertEqual(XTouchProtocol.unit(fromValue14: 16383), 1.0)
        XCTAssertEqual(XTouchProtocol.unit(fromValue14: -100), 0.0) // clamped
        XCTAssertEqual(XTouchProtocol.unit(fromValue14: 99999), 1.0) // clamped
    }
}
