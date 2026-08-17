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
}
