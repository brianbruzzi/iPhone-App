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

/// A pad pattern that lights exactly one corner pad, rest black — for tracking where a
/// single point lands after `PatternEngine.padRotation` is applied.
private struct CornerMarkedPadPattern: PadPattern {
    static let id = "cornerMarked"
    static let displayName = "Corner Marked"

    func render(elapsed: TimeInterval, beat: BeatClockSnapshot, params: PadPatternParams) -> PixelGrid {
        var grid = PixelGrid.allBlack
        grid[0, 0] = .white
        return grid
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

    // MARK: - Pad rotation

    func testDefaultPadRotationLeavesTheGridUnchanged() {
        let engine = PatternEngine(faderPattern: WaveFaderPattern(), padPattern: CornerMarkedPadPattern())
        var emitted: PixelGrid?
        engine.onPadFrame = { emitted = $0 }
        engine.tick(elapsed: 0, beat: .idle, components: .pads)

        XCTAssertEqual(emitted?[0, 0], .white)
        XCTAssertEqual(emitted?[7, 0], .black)
    }

    func testPadRotationIsAppliedToTheEmittedGrid() {
        let engine = PatternEngine(faderPattern: WaveFaderPattern(), padPattern: CornerMarkedPadPattern())
        engine.padRotation = .degrees90
        var emitted: PixelGrid?
        engine.onPadFrame = { emitted = $0 }
        engine.tick(elapsed: 0, beat: .idle, components: .pads)

        // A 90 degree rotation carries the top-left corner to the top-right.
        XCTAssertEqual(emitted?[7, 0], .white)
        XCTAssertEqual(emitted?[0, 0], .black)
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

    // MARK: - External (hand-moved) fader positions

    func testExternalFaderPositionUpdatesLastKnownValues() {
        let engine = PatternEngine()
        engine.noteExternalFaderPosition(index: 3, value: 0.8)
        XCTAssertEqual(engine.lastKnownFaderValues[3], 0.8, accuracy: 1e-9)
    }

    func testExternalFaderPositionClampsAndRejectsGarbage() {
        let engine = PatternEngine()
        engine.noteExternalFaderPosition(index: 0, value: 1.7)
        XCTAssertEqual(engine.lastKnownFaderValues[0], 1.0, accuracy: 1e-9)

        engine.noteExternalFaderPosition(index: 1, value: .nan)
        XCTAssertEqual(engine.lastKnownFaderValues[1], 0.5, accuracy: 1e-9, "NaN must be ignored")

        engine.noteExternalFaderPosition(index: 99, value: 0.5) // out of range: must not crash
    }

    /// The end-to-end reason this API exists: a touched fader emits NaN from the pattern,
    /// but an external position report keeps the mirror live at the hand's position.
    func testExternalPositionFeedsSurfacePatternWhileFaderIsTouched() {
        let engine = PatternEngine(faderPattern: ConstantFaderPattern(value: 0.2), padPattern: PlasmaWavePattern())
        engine.tick(elapsed: 0, beat: .idle, components: .faders)
        engine.touchedFaders = [2]
        engine.noteExternalFaderPosition(index: 2, value: 0.9)

        var receivedFaders: [Double] = []
        engine.surfacePattern = RecordingSurfacePattern { receivedFaders = $0 }
        engine.tick(elapsed: 1, beat: .idle, components: [.faders, .surface])

        XCTAssertEqual(receivedFaders[2], 0.9, accuracy: 1e-9, "surface pattern should see the hand position, not the stale pre-touch value")
    }

    // MARK: - Right-hand section splice

    /// Channel strip Off + right section Full Surface: only notes 40+ light, and the
    /// encoder rings / scribble strips (physically part of the channel strips) stay with
    /// the channel-strip pattern rather than leaking in from the right-hand render.
    func testRightSectionPatternOverridesOnlyRightSectionButtons() {
        let engine = PatternEngine()
        engine.surfacePattern = SurfaceOffPattern()
        engine.rightSectionPattern = FullSurfaceSurfacePattern()

        var emitted: SurfaceFrame?
        engine.onSurfaceFrame = { emitted = $0 }
        engine.tick(elapsed: 0, beat: .idle, components: .surface)

        guard let frame = emitted else { return XCTFail("no surface frame emitted") }

        for note in XTouchSurfaceProtocol.rightSectionButtonNotes {
            XCTAssertNotEqual(frame[buttonNote: note], .off, "right-section note \(note) should be lit")
        }
        for note in XTouchSurfaceProtocol.channelStripZones.flatMap({ $0.notes }) {
            XCTAssertEqual(frame[buttonNote: note], .off, "channel-strip note \(note) must follow the channel-strip pattern")
        }
        XCTAssertEqual(frame.rings, SurfaceFrame.allOff.rings, "rings belong to the channel-strip pattern")
        XCTAssertEqual(frame.scribbleColors, SurfaceFrame.allOff.scribbleColors)
        XCTAssertEqual(frame.scribbleTexts, SurfaceFrame.allOff.scribbleTexts)
    }

    /// The mirror image: the right section can go dark without touching the fader show.
    func testChannelStripSurvivesWhenRightSectionIsOff() {
        let engine = PatternEngine()
        engine.surfacePattern = FullSurfaceSurfacePattern()
        engine.rightSectionPattern = SurfaceOffPattern()

        var emitted: SurfaceFrame?
        engine.onSurfaceFrame = { emitted = $0 }
        engine.tick(elapsed: 0, beat: .idle, components: .surface)

        guard let frame = emitted else { return XCTFail("no surface frame emitted") }

        for note in XTouchSurfaceProtocol.rightSectionButtonNotes {
            XCTAssertEqual(frame[buttonNote: note], .off, "right-section note \(note) should be dark")
        }
        for note in XTouchSurfaceProtocol.channelStripZones.flatMap({ $0.notes }) {
            XCTAssertNotEqual(frame[buttonNote: note], .off, "channel-strip note \(note) should still be lit")
        }
        // Full Surface's rings/scribble output survives the splice untouched.
        XCTAssertTrue(frame.rings.allSatisfy { $0.position == 11 })
        XCTAssertTrue(frame.scribbleColors.allSatisfy { $0 == .white })
    }

    func testRightSectionDefaultsToFollowingTheFaders() {
        let engine = PatternEngine()
        XCTAssertEqual(type(of: engine.rightSectionPattern).id, FaderMirrorSurfacePattern.id)
    }

    func testRightSectionPatternReceivesItsOwnParams() {
        let engine = PatternEngine()
        engine.surfaceParams = SurfacePatternParams(speed: 1.0, intensity: 1.0)
        engine.rightSectionParams = SurfacePatternParams(speed: 3.0, intensity: 0.25)

        var received: SurfacePatternParams?
        engine.rightSectionPattern = ParamRecordingSurfacePattern { received = $0 }
        engine.tick(elapsed: 0, beat: .idle, components: .surface)

        XCTAssertEqual(received, SurfacePatternParams(speed: 3.0, intensity: 0.25))
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

/// Captures the params it was called with, for asserting the right-hand section reads
/// `rightSectionParams` rather than `surfaceParams`.
private struct ParamRecordingSurfacePattern: SurfacePattern {
    static let id = "paramRecording"
    static let displayName = "Param Recording"
    let onRender: (SurfacePatternParams) -> Void

    func render(elapsed: TimeInterval, beat: BeatClockSnapshot, params: SurfacePatternParams, faders: [Double]) -> SurfaceFrame {
        onRender(params)
        return .allOff
    }
}
