import XCTest
@testable import FaderLabCore

/// A fixed pattern that always returns the same fader values, for isolating
/// `PatternEngine`'s own behavior (touch-skip, beat-sync toggle) from pattern math.
private struct ConstantFaderPattern: FaderPattern {
    static let id = "constant"
    static let displayName = "Constant"
    let value: Double

    func faderValues(elapsed: TimeInterval, beat: BeatClockSnapshot, params: FaderPatternParams) -> [Double] {
        Array(repeating: value, count: XTouchProtocol.faderCount)
    }
}

/// A pad pattern that paints the whole grid a single color derived from `beat.beatIndex`,
/// so tests can observe whether the engine passed the live beat or `.idle`.
private struct BeatIndexColorPadPattern: PadPattern {
    static let id = "beatIndexColor"
    static let displayName = "Beat Index Color"

    func render(elapsed: TimeInterval, beat: BeatClockSnapshot, params: PadPatternParams) -> PixelGrid {
        PixelGrid(repeating: RGBColor(r: UInt8(beat.beatIndex % 256), g: 0, b: 0))
    }
}

final class PatternEngineTests: XCTestCase {

    func testTouchedFadersAreSkippedWithNaN() {
        let engine = PatternEngine(faderPattern: ConstantFaderPattern(value: 1.0), padPattern: PlasmaWavePattern())
        engine.touchedFaders = [2, 5]

        var received: [Double] = []
        engine.onFaderFrame = { received = $0 }
        engine.tick(elapsed: 0, beat: .idle)

        XCTAssertEqual(received.count, XTouchProtocol.faderCount)
        for (index, value) in received.enumerated() {
            if index == 2 || index == 5 {
                XCTAssertTrue(value.isNaN, "touched fader \(index) should be skipped")
            } else {
                XCTAssertEqual(value, 1.0, accuracy: 1e-9)
            }
        }
    }

    func testSyncToBeatOffPassesIdleSnapshotToPatterns() {
        let engine = PatternEngine(faderPattern: WaveFaderPattern(), padPattern: BeatIndexColorPadPattern())
        engine.syncToBeat = false

        var receivedGrid: PixelGrid?
        engine.onPadFrame = { receivedGrid = $0 }

        let liveBeat = BeatClockSnapshot(bpm: 128, phase: 0.5, beatIndex: 42, isLive: true)
        engine.tick(elapsed: 0, beat: liveBeat)

        // .idle has beatIndex 0, so the pad pattern should have painted red==0, not 42.
        XCTAssertEqual(receivedGrid?[0, 0].r, 0)
    }

    func testSyncToBeatOnPassesLiveSnapshotToPatterns() {
        let engine = PatternEngine(faderPattern: WaveFaderPattern(), padPattern: BeatIndexColorPadPattern())
        engine.syncToBeat = true

        var receivedGrid: PixelGrid?
        engine.onPadFrame = { receivedGrid = $0 }

        let liveBeat = BeatClockSnapshot(bpm: 128, phase: 0.5, beatIndex: 42, isLive: true)
        engine.tick(elapsed: 0, beat: liveBeat)

        XCTAssertEqual(receivedGrid?[0, 0].r, 42)
    }

    func testEmitsBothFrameKindsEveryTick() {
        let engine = PatternEngine()
        var faderCalls = 0
        var padCalls = 0
        engine.onFaderFrame = { _ in faderCalls += 1 }
        engine.onPadFrame = { _ in padCalls += 1 }

        engine.tick(elapsed: 0, beat: .idle)
        engine.tick(elapsed: 1, beat: .idle)

        XCTAssertEqual(faderCalls, 2)
        XCTAssertEqual(padCalls, 2)
    }

    // MARK: - TickComponents

    func testComponentsFilterWhichCallbacksFire() {
        let engine = PatternEngine()
        var faderCalls = 0
        var padCalls = 0
        var surfaceCalls = 0
        engine.onFaderFrame = { _ in faderCalls += 1 }
        engine.onPadFrame = { _ in padCalls += 1 }
        engine.onSurfaceFrame = { _ in surfaceCalls += 1 }

        engine.tick(elapsed: 0, beat: .idle, components: .faders)
        XCTAssertEqual(faderCalls, 1)
        XCTAssertEqual(padCalls, 0)
        XCTAssertEqual(surfaceCalls, 0)

        engine.tick(elapsed: 0, beat: .idle, components: [.pads, .surface])
        XCTAssertEqual(faderCalls, 1)
        XCTAssertEqual(padCalls, 1)
        XCTAssertEqual(surfaceCalls, 1)
    }

    func testDefaultComponentsIsAll() {
        let engine = PatternEngine()
        var faderCalls = 0
        var padCalls = 0
        var surfaceCalls = 0
        engine.onFaderFrame = { _ in faderCalls += 1 }
        engine.onPadFrame = { _ in padCalls += 1 }
        engine.onSurfaceFrame = { _ in surfaceCalls += 1 }

        engine.tick(elapsed: 0, beat: .idle)

        XCTAssertEqual(faderCalls, 1)
        XCTAssertEqual(padCalls, 1)
        XCTAssertEqual(surfaceCalls, 1)
    }

    // MARK: - lastKnownFaderValues

    func testLastKnownFaderValuesStartsNeutral() {
        let engine = PatternEngine()
        XCTAssertEqual(engine.lastKnownFaderValues, Array(repeating: 0.5, count: XTouchProtocol.faderCount))
    }

    func testLastKnownFaderValuesUpdatesFromFiniteFrames() {
        let engine = PatternEngine(faderPattern: ConstantFaderPattern(value: 0.75), padPattern: PlasmaWavePattern())
        engine.tick(elapsed: 0, beat: .idle, components: .faders)

        XCTAssertEqual(engine.lastKnownFaderValues, Array(repeating: 0.75, count: XTouchProtocol.faderCount))
    }

    func testLastKnownFaderValuesHoldsLastValueForTouchedFaders() {
        let engine = PatternEngine(faderPattern: ConstantFaderPattern(value: 0.2), padPattern: PlasmaWavePattern())
        engine.tick(elapsed: 0, beat: .idle, components: .faders)

        engine.touchedFaders = [3]
        engine.faderPattern = ConstantFaderPattern(value: 0.9)
        engine.tick(elapsed: 1, beat: .idle, components: .faders)

        // Fader 3 was touched (emits NaN this tick) -> keeps its pre-touch value, 0.2.
        XCTAssertEqual(engine.lastKnownFaderValues[3], 0.2, accuracy: 1e-9)
        // Untouched faders track the new pattern output.
        XCTAssertEqual(engine.lastKnownFaderValues[0], 0.9, accuracy: 1e-9)
    }

    func testSurfacePatternReceivesLastKnownFaderValues() {
        let engine = PatternEngine(faderPattern: ConstantFaderPattern(value: 0.3), padPattern: PlasmaWavePattern())
        engine.tick(elapsed: 0, beat: .idle, components: .faders)

        var receivedFaders: [Double] = []
        engine.surfacePattern = RecordingSurfacePattern { faders in receivedFaders = faders }
        engine.tick(elapsed: 0, beat: .idle, components: .surface)

        XCTAssertEqual(receivedFaders, Array(repeating: 0.3, count: XTouchProtocol.faderCount))
    }
}

/// Captures the `faders` array it was called with, for asserting `PatternEngine` wires
/// `lastKnownFaderValues` through to surface patterns correctly.
private struct RecordingSurfacePattern: SurfacePattern {
    static let id = "recording"
    static let displayName = "Recording"
    let onRender: ([Double]) -> Void

    func render(elapsed: TimeInterval, beat: BeatClockSnapshot, params: SurfacePatternParams, faders: [Double]) -> SurfaceFrame {
        onRender(faders)
        return .allOff
    }
}
