import XCTest
@testable import FaderLabCore

final class FaderFrameGateTests: XCTestCase {

    private let nineFaders = [Double](repeating: 0.5, count: XTouchProtocol.faderCount)

    func testFirstFrameSendsEveryFader() {
        let gate = FaderFrameGate()
        let messages = gate.messages(for: nineFaders, mode: .mackieControl)
        XCTAssertEqual(messages.count, nineFaders.count)
        for (index, message) in messages.enumerated() {
            XCTAssertEqual(message, XTouchProtocol.pitchBendBytes(fader: index, unitValue: 0.5))
        }
    }

    func testRepeatingSameValueSuppressesResend() {
        let gate = FaderFrameGate()
        _ = gate.messages(for: nineFaders, mode: .mackieControl)
        let second = gate.messages(for: nineFaders, mode: .mackieControl)
        XCTAssertEqual(second, [])
    }

    func testChangedFaderResendsOnlyThatFader() {
        let gate = FaderFrameGate()
        _ = gate.messages(for: nineFaders, mode: .mackieControl)

        var changed = nineFaders
        changed[2] = 0.9
        let messages = gate.messages(for: changed, mode: .mackieControl)

        XCTAssertEqual(messages, [XTouchProtocol.pitchBendBytes(fader: 2, unitValue: 0.9)])
    }

    func testNaNEntryIsSkippedAndCachePreserved() {
        let gate = FaderFrameGate()
        _ = gate.messages(for: nineFaders, mode: .mackieControl)

        var touched = nineFaders
        touched[4] = .nan
        let messages = gate.messages(for: touched, mode: .mackieControl)
        XCTAssertEqual(messages, [], "NaN (touched) faders must not be sent")

        // Cache for fader 4 must be untouched by the NaN pass: resending the same value
        // it had before the touch must still be suppressed once the hand lifts.
        let afterRelease = gate.messages(for: nineFaders, mode: .mackieControl)
        XCTAssertEqual(afterRelease, [], "cache should still remember fader 4's pre-touch value")
    }

    func testInvalidateSingleFaderForcesResend() {
        let gate = FaderFrameGate()
        _ = gate.messages(for: nineFaders, mode: .mackieControl)

        gate.invalidate(fader: 5)
        let messages = gate.messages(for: nineFaders, mode: .mackieControl)

        XCTAssertEqual(messages, [XTouchProtocol.pitchBendBytes(fader: 5, unitValue: 0.5)])
    }

    func testInvalidateAllForcesFullResend() {
        let gate = FaderFrameGate()
        _ = gate.messages(for: nineFaders, mode: .mackieControl)

        gate.invalidateAll()
        let messages = gate.messages(for: nineFaders, mode: .mackieControl)

        XCTAssertEqual(messages.count, nineFaders.count)
    }

    func testModeChangeFlushesCacheEvenAtSameEncodedValue() {
        let gate = FaderFrameGate()
        _ = gate.messages(for: nineFaders, mode: .mackieControl)

        let messages = gate.messages(for: nineFaders, mode: .ctrl)

        XCTAssertEqual(messages.count, nineFaders.count)
        for (index, message) in messages.enumerated() {
            XCTAssertEqual(message, XTouchCtrlProtocol.faderBytes(fader: index, unitValue: 0.5))
        }
    }

    func testHUIModeAlwaysSendsNothing() {
        let gate = FaderFrameGate()
        let messages = gate.messages(for: nineFaders, mode: .hui)
        XCTAssertEqual(messages, [])
    }

    func testSwitchingBackFromHUIProducesFullRepaint() {
        let gate = FaderFrameGate()
        _ = gate.messages(for: nineFaders, mode: .mackieControl)
        _ = gate.messages(for: nineFaders, mode: .hui)

        let messages = gate.messages(for: nineFaders, mode: .mackieControl)

        XCTAssertEqual(messages.count, nineFaders.count)
    }
}
