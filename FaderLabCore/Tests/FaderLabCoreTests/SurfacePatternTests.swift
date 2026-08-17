import XCTest
@testable import FaderLabCore

final class SurfacePatternTests: XCTestCase {

    private let nineFaders = [Double](repeating: 0.5, count: XTouchProtocol.faderCount)

    // MARK: - Registry-wide sanity

    func testAllPatternsProduceWellFormedFramesAtAssortedTimes() {
        let params = SurfacePatternParams()
        let beats: [BeatClockSnapshot] = [
            .idle,
            BeatClockSnapshot(bpm: 120, phase: 0, beatIndex: 0, isLive: true),
            BeatClockSnapshot(bpm: 128, phase: 0.7, beatIndex: 17, isLive: true),
        ]
        for pattern in SurfacePatterns.all {
            for beat in beats {
                for elapsed in [0.0, 1.23, 60.0] {
                    let frame = pattern.render(elapsed: elapsed, beat: beat, params: params, faders: nineFaders)
                    XCTAssertEqual(frame.buttons.count, XTouchSurfaceProtocol.animatableButtonNotes.count, "\(type(of: pattern).id)")
                    XCTAssertEqual(frame.rings.count, XTouchSurfaceProtocol.stripCount, "\(type(of: pattern).id)")
                    XCTAssertEqual(frame.scribbleColors.count, XTouchSurfaceProtocol.stripCount, "\(type(of: pattern).id)")
                    XCTAssertEqual(frame.scribbleTexts.count, XTouchSurfaceProtocol.stripCount, "\(type(of: pattern).id)")
                }
            }
        }
    }

    func testAllPatternsAreDeterministic() {
        let params = SurfacePatternParams(speed: 1.3, intensity: 0.6)
        let beat = BeatClockSnapshot(bpm: 100, phase: 0.4, beatIndex: 9, isLive: true)
        for pattern in SurfacePatterns.all {
            let a = pattern.render(elapsed: 4.2, beat: beat, params: params, faders: nineFaders)
            let b = pattern.render(elapsed: 4.2, beat: beat, params: params, faders: nineFaders)
            XCTAssertEqual(a, b, "\(type(of: pattern).id)")
        }
    }

    func testRegistryContainsAllBuiltInPatterns() {
        let ids = Set(SurfacePatterns.all.map { type(of: $0).id })
        XCTAssertEqual(ids, ["beatFlash", "chase", "faderMirror", "off"])
    }

    // MARK: - Off

    func testSurfaceOffPatternIsAlwaysAllOff() {
        let frame = SurfaceOffPattern().render(
            elapsed: 99, beat: BeatClockSnapshot(bpm: 140, phase: 0.9, beatIndex: 3, isLive: true),
            params: SurfacePatternParams(), faders: nineFaders
        )
        XCTAssertEqual(frame, .allOff)
    }

    // MARK: - Beat Flash

    func testBeatFlashZoneAdvancesWithBeatIndex() {
        let params = SurfacePatternParams()
        let onBeatZero = BeatClockSnapshot(bpm: 120, phase: 0, beatIndex: 0, isLive: true)
        let onBeatOne = BeatClockSnapshot(bpm: 120, phase: 0, beatIndex: 1, isLive: true)

        let frameZero = ZoneBeatFlashSurfacePattern().render(elapsed: 0, beat: onBeatZero, params: params, faders: nineFaders)
        let frameOne = ZoneBeatFlashSurfacePattern().render(elapsed: 0, beat: onBeatOne, params: params, faders: nineFaders)

        // beatIndex 0 -> REC zone, beatIndex 1 -> SOLO zone.
        XCTAssertEqual(frameZero[buttonNote: XTouchSurfaceProtocol.ButtonZone.rec.notes[0]], .solid)
        XCTAssertEqual(frameOne[buttonNote: XTouchSurfaceProtocol.ButtonZone.solo.notes[0]], .solid)
        XCTAssertEqual(frameOne[buttonNote: XTouchSurfaceProtocol.ButtonZone.rec.notes[0]], .off)
    }

    func testBeatFlashCutsOffPastIntensityPhase() {
        let params = SurfacePatternParams(intensity: 0.3)
        let earlyPhase = BeatClockSnapshot(bpm: 120, phase: 0.1, beatIndex: 0, isLive: true)
        let latePhase = BeatClockSnapshot(bpm: 120, phase: 0.9, beatIndex: 0, isLive: true)

        let early = ZoneBeatFlashSurfacePattern().render(elapsed: 0, beat: earlyPhase, params: params, faders: nineFaders)
        let late = ZoneBeatFlashSurfacePattern().render(elapsed: 0, beat: latePhase, params: params, faders: nineFaders)

        XCTAssertEqual(early[buttonNote: XTouchSurfaceProtocol.ButtonZone.rec.notes[0]], .solid)
        XCTAssertEqual(late[buttonNote: XTouchSurfaceProtocol.ButtonZone.rec.notes[0]], .off)
    }

    // MARK: - Chase

    func testChaseColumnFollowsBeatIndexWhenLive() {
        let params = SurfacePatternParams()
        let beat = BeatClockSnapshot(bpm: 120, phase: 0, beatIndex: 3, isLive: true)
        let frame = ButtonChaseSurfacePattern().render(elapsed: 0, beat: beat, params: params, faders: nineFaders)

        XCTAssertEqual(frame[buttonNote: XTouchSurfaceProtocol.ButtonZone.rec.notes[3]], .solid)
        for column in 0..<XTouchSurfaceProtocol.stripCount where column != 3 {
            XCTAssertEqual(frame[buttonNote: XTouchSurfaceProtocol.ButtonZone.rec.notes[column]], .off)
        }
    }

    func testChaseColumnFollowsElapsedWhenNotLive() {
        let params = SurfacePatternParams(speed: 1.0)
        let idleBeat = BeatClockSnapshot.idle // isLive == false
        // elapsed * speed * 2 = elapsed * 2; elapsed=1.5 -> column 3
        let frame = ButtonChaseSurfacePattern().render(elapsed: 1.5, beat: idleBeat, params: params, faders: nineFaders)

        XCTAssertEqual(frame[buttonNote: XTouchSurfaceProtocol.ButtonZone.rec.notes[3]], .solid)
    }

    // MARK: - Fader Mirror

    func testFaderMirrorRingPositionsTrackLinkedFaders() {
        let faders: [Double] = [0.0, 0.5, 1.0] + Array(repeating: 0.5, count: 6)
        let frame = FaderMirrorSurfacePattern().render(
            elapsed: 0, beat: .idle, params: SurfacePatternParams(), faders: faders
        )

        XCTAssertEqual(frame.rings[0].position, 0)
        XCTAssertEqual(frame.rings[1].position, 6)
        XCTAssertEqual(frame.rings[2].position, 11)
    }

    func testFaderMirrorTreatsMissingEntriesAsZero() {
        // Fewer than 8 entries — must not crash, and unmapped strips read as level 0.
        let shortFaders: [Double] = [0.8]
        let frame = FaderMirrorSurfacePattern().render(
            elapsed: 0, beat: .idle, params: SurfacePatternParams(), faders: shortFaders
        )

        XCTAssertEqual(frame.rings[0].position, Int((0.8 * 11).rounded()))
        XCTAssertEqual(frame.rings[1].position, 0)
        XCTAssertEqual(frame.rings[7].position, 0)
    }

    func testFaderMirrorLightsSelectAndMuteAtExtremes() {
        let faders: [Double] = [0.95, 0.05] + Array(repeating: 0.5, count: 7)
        let frame = FaderMirrorSurfacePattern().render(
            elapsed: 0, beat: .idle, params: SurfacePatternParams(), faders: faders
        )

        XCTAssertEqual(frame[buttonNote: XTouchSurfaceProtocol.ButtonZone.select.notes[0]], .solid)
        XCTAssertEqual(frame[buttonNote: XTouchSurfaceProtocol.ButtonZone.mute.notes[1]], .solid)
        XCTAssertEqual(frame[buttonNote: XTouchSurfaceProtocol.ButtonZone.select.notes[1]], .off)
        XCTAssertEqual(frame[buttonNote: XTouchSurfaceProtocol.ButtonZone.mute.notes[0]], .off)
    }
}
