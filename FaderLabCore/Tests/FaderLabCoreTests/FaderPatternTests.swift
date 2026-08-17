import XCTest
@testable import FaderLabCore

final class FaderPatternTests: XCTestCase {

    // MARK: - Wave

    func testWaveReturnsNineValues() {
        let values = WaveFaderPattern().faderValues(elapsed: 0, beat: .idle, params: FaderPatternParams())
        XCTAssertEqual(values.count, XTouchProtocol.faderCount)
    }

    func testWaveFirstFaderAtZeroPhaseIsBaseLevel() {
        // Fader 0 has zero phase offset, so at t=0, sin(0) == 0 -> value == baseLevel exactly.
        let params = FaderPatternParams(speed: 1, amplitude: 1, baseLevel: 0.5)
        let values = WaveFaderPattern().faderValues(elapsed: 0, beat: .idle, params: params)
        XCTAssertEqual(values[0], 0.5, accuracy: 1e-9)
    }

    func testWaveClampsToUnitRange() {
        let params = FaderPatternParams(speed: 1, amplitude: 5, baseLevel: 0.5)
        let values = WaveFaderPattern().faderValues(elapsed: 0.123, beat: .idle, params: params)
        for value in values {
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 1)
        }
    }

    // MARK: - Beat pulse

    func testBeatPulseAtBeatOnsetIsPeak() {
        let params = FaderPatternParams(speed: 1, amplitude: 1, baseLevel: 0.5)
        let beat = BeatClockSnapshot(bpm: 120, phase: 0, beatIndex: 0, isLive: true)
        let values = BeatPulseFaderPattern().faderValues(elapsed: 0, beat: beat, params: params)
        for value in values {
            XCTAssertEqual(value, 1.0, accuracy: 1e-9) // baseLevel(0.5) + amplitude*0.5(0.5) * envelope(1) == 1.0
        }
    }

    func testBeatPulseDecaysAwayFromBeatOnset() {
        let params = FaderPatternParams(speed: 1, amplitude: 1, baseLevel: 0.5)
        let onBeat = BeatClockSnapshot(bpm: 120, phase: 0, beatIndex: 0, isLive: true)
        let midBeat = BeatClockSnapshot(bpm: 120, phase: 0.5, beatIndex: 0, isLive: true)
        let onBeatValue = BeatPulseFaderPattern().faderValues(elapsed: 0, beat: onBeat, params: params)[0]
        let midBeatValue = BeatPulseFaderPattern().faderValues(elapsed: 0, beat: midBeat, params: params)[0]
        XCTAssertLessThan(midBeatValue, onBeatValue)
    }

    func testBeatPulseIsUnisonAcrossAllFaders() {
        let params = FaderPatternParams()
        let beat = BeatClockSnapshot(bpm: 100, phase: 0.3, beatIndex: 2, isLive: true)
        let values = BeatPulseFaderPattern().faderValues(elapsed: 0, beat: beat, params: params)
        XCTAssertEqual(Set(values.map { ($0 * 1e9).rounded() }).count, 1, "all faders should move together")
    }

    // MARK: - Beat chase

    func testBeatChaseRaisesOnlyTheActiveFader() {
        let params = FaderPatternParams(speed: 1, amplitude: 1, baseLevel: 0.5)
        let beat = BeatClockSnapshot(bpm: 120, phase: 0, beatIndex: 0, isLive: true)
        let values = BeatChaseFaderPattern().faderValues(elapsed: 0, beat: beat, params: params)
        XCTAssertEqual(values[0], 1.0, accuracy: 1e-9)
        for index in 1..<XTouchProtocol.faderCount {
            XCTAssertEqual(values[index], 0.0, accuracy: 1e-9)
        }
    }

    func testBeatChaseAdvancesAndWrapsWithBeatIndex() {
        let params = FaderPatternParams(speed: 1, amplitude: 1, baseLevel: 0.5)
        let beatOne = BeatClockSnapshot(bpm: 120, phase: 0, beatIndex: 1, isLive: true)
        XCTAssertEqual(BeatChaseFaderPattern().faderValues(elapsed: 0, beat: beatOne, params: params)[1], 1.0, accuracy: 1e-9)

        // beatIndex 9 wraps back to fader 0 (faderCount == 9).
        let beatNine = BeatClockSnapshot(bpm: 120, phase: 0, beatIndex: 9, isLive: true)
        XCTAssertEqual(BeatChaseFaderPattern().faderValues(elapsed: 0, beat: beatNine, params: params)[0], 1.0, accuracy: 1e-9)
    }

    // MARK: - Manual off

    func testManualOffReturnsAllNaN() {
        let values = ManualOffFaderPattern().faderValues(elapsed: 0, beat: .idle, params: FaderPatternParams())
        XCTAssertEqual(values.count, XTouchProtocol.faderCount)
        XCTAssertTrue(values.allSatisfy { $0.isNaN })
    }

    // MARK: - Registry

    func testRegistryContainsAllBuiltInPatterns() {
        let ids = Set(FaderPatterns.all.map { type(of: $0).id })
        XCTAssertEqual(ids, ["wave", "beatPulse", "beatChase", "manualOff"])
    }
}
