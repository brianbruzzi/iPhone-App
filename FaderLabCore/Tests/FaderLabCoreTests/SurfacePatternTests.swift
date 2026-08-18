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
        XCTAssertEqual(ids, ["fullSurface", "beatFlash", "chase", "faderMirror", "off"])
    }

    // MARK: - Off

    func testSurfaceOffPatternIsAlwaysAllOff() {
        let frame = SurfaceOffPattern().render(
            elapsed: 99, beat: BeatClockSnapshot(bpm: 140, phase: 0.9, beatIndex: 3, isLive: true),
            params: SurfacePatternParams(), faders: nineFaders
        )
        XCTAssertEqual(frame, .allOff)
    }

    // MARK: - Full Surface

    func testFullSurfaceLightsEverythingSolidOrBlinkNeverOff() {
        let frame = FullSurfaceSurfacePattern().render(elapsed: 0, beat: .idle, params: SurfacePatternParams(), faders: nineFaders)
        XCTAssertFalse(frame.buttons.contains(.off), "Full Surface is the 'everything is on' pattern — nothing should be dark")
    }

    func testFullSurfaceBlinkBandTravelsOverTime() {
        let params = SurfacePatternParams(speed: 1.0)
        let frameA = FullSurfaceSurfacePattern().render(elapsed: 0, beat: .idle, params: params, faders: nineFaders)
        let frameB = FullSurfaceSurfacePattern().render(elapsed: 3.0, beat: .idle, params: params, faders: nineFaders)

        XCTAssertNotEqual(frameA.buttons, frameB.buttons, "the rolling blink band should move as elapsed advances")
    }

    // MARK: - Beat Flash

    func testBeatFlashAllZonesSolidAtDownbeat() {
        let params = SurfacePatternParams(intensity: 1.0)
        let beat = BeatClockSnapshot(bpm: 120, phase: 0, beatIndex: 0, isLive: true)
        let frame = ZoneBeatFlashSurfacePattern().render(elapsed: 0, beat: beat, params: params, faders: nineFaders)

        // Every button is solid on the downbeat except the Play button, which is always
        // forced to blink as a constant "heartbeat" indicator.
        let nonSolid = frame.buttons.filter { $0 != .solid }
        XCTAssertEqual(nonSolid.count, 1)
    }

    func testBeatFlashDropOrderRotatesWithBeatIndex() {
        let params = SurfacePatternParams(intensity: 0.1)
        // Just past cutoff (0.1), with intensity 0.1 exactly one zone has dropped — the
        // rotation should determine *which* zone, in ButtonZone.allCases order.
        let beatZero = BeatClockSnapshot(bpm: 120, phase: 0.16, beatIndex: 0, isLive: true)
        let beatOne = BeatClockSnapshot(bpm: 120, phase: 0.16, beatIndex: 1, isLive: true)

        let frameZero = ZoneBeatFlashSurfacePattern().render(elapsed: 0, beat: beatZero, params: params, faders: nineFaders)
        let frameOne = ZoneBeatFlashSurfacePattern().render(elapsed: 0, beat: beatOne, params: params, faders: nineFaders)

        XCTAssertEqual(frameZero[buttonNote: XTouchSurfaceProtocol.ButtonZone.rec.notes[0]], .blink)
        XCTAssertEqual(frameZero[buttonNote: XTouchSurfaceProtocol.ButtonZone.solo.notes[0]], .solid)

        XCTAssertEqual(frameOne[buttonNote: XTouchSurfaceProtocol.ButtonZone.solo.notes[0]], .blink)
        XCTAssertEqual(frameOne[buttonNote: XTouchSurfaceProtocol.ButtonZone.rec.notes[0]], .solid)
    }

    func testBeatFlashNeverGoesFullyDark() {
        let params = SurfacePatternParams(intensity: 0.1)
        let nearEndOfBeat = BeatClockSnapshot(bpm: 120, phase: 0.99, beatIndex: 0, isLive: true)
        let frame = ZoneBeatFlashSurfacePattern().render(elapsed: 0, beat: nearEndOfBeat, params: params, faders: nineFaders)

        XCTAssertFalse(frame.buttons.contains(.off), "dropped zones go to blink, never off")
        XCTAssertTrue(frame.buttons.contains(.blink), "most zones should have dropped out by the end of a low-intensity beat")
    }

    // MARK: - Chase

    func testChaseAccentsTheSweepColumnAcrossEveryZone() {
        let beat = BeatClockSnapshot(bpm: 120, phase: 0, beatIndex: 3, isLive: true)
        let frame = ButtonChaseSurfacePattern().render(elapsed: 0, beat: beat, params: SurfacePatternParams(), faders: nineFaders)

        for zone in XTouchSurfaceProtocol.ButtonZone.allCases {
            let notes = zone.notes
            XCTAssertEqual(frame[buttonNote: notes[3 % notes.count]], .solid, "\(zone)")
        }
    }

    func testChaseBaselineIsBlinkNotOff() {
        let beat = BeatClockSnapshot(bpm: 120, phase: 0, beatIndex: 3, isLive: true)
        let frame = ButtonChaseSurfacePattern().render(elapsed: 0, beat: beat, params: SurfacePatternParams(), faders: nineFaders)

        XCTAssertFalse(frame.buttons.contains(.off))
        // A note off the current sweep column within an 8-note zone should be blinking.
        XCTAssertEqual(frame[buttonNote: XTouchSurfaceProtocol.ButtonZone.rec.notes[0]], .blink)
    }

    func testChaseColumnFollowsElapsedWhenNotLive() {
        let params = SurfacePatternParams(speed: 1.0)
        let idleBeat = BeatClockSnapshot.idle // isLive == false
        // elapsed * speed * 2 = elapsed * 2; elapsed=1.5 -> column 3
        let frame = ButtonChaseSurfacePattern().render(elapsed: 1.5, beat: idleBeat, params: params, faders: nineFaders)

        XCTAssertEqual(frame[buttonNote: XTouchSurfaceProtocol.ButtonZone.rec.notes[3]], .solid)
    }

    /// Every zone is now indexed uniformly via modulo-wrap (`notes[column % notes.count]`),
    /// safe regardless of a zone's actual note count — this sweeps every column and every
    /// zone-selecting beatIndex to confirm nothing traps.
    func testChaseAndFaderMirrorNeverTrapAcrossAllColumnsAndStrips() {
        let params = SurfacePatternParams()
        let chase = ButtonChaseSurfacePattern()
        let mirror = FaderMirrorSurfacePattern()

        for column in 0..<8 {
            let liveBeat = BeatClockSnapshot(bpm: 120, phase: 0, beatIndex: column, isLive: true)
            let chaseFrame = chase.render(elapsed: 0, beat: liveBeat, params: params, faders: nineFaders)
            XCTAssertEqual(chaseFrame.buttons.count, XTouchSurfaceProtocol.animatableButtonNotes.count)

            let mirrorFrame = mirror.render(elapsed: 0, beat: .idle, params: params, faders: nineFaders)
            XCTAssertEqual(mirrorFrame.buttons.count, XTouchSurfaceProtocol.animatableButtonNotes.count)
        }

        for step in 0..<20 {
            let elapsed = Double(step) * 0.5
            _ = chase.render(elapsed: elapsed, beat: .idle, params: params, faders: nineFaders)
        }
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
        // Not-yet-extreme strips drop to blink, never off.
        XCTAssertEqual(frame[buttonNote: XTouchSurfaceProtocol.ButtonZone.select.notes[1]], .blink)
        XCTAssertEqual(frame[buttonNote: XTouchSurfaceProtocol.ButtonZone.mute.notes[0]], .blink)
    }

    func testFaderMirrorLadderZonesLightProgressivelyWithLevel() {
        // Level 0.9 clears every ladder rung's threshold (highest is .globalView at 0.8).
        let faders: [Double] = [0.9] + Array(repeating: 0.5, count: 8)
        let frame = FaderMirrorSurfacePattern().render(elapsed: 0, beat: .idle, params: SurfacePatternParams(), faders: faders)

        XCTAssertEqual(frame[buttonNote: XTouchSurfaceProtocol.ButtonZone.rec.notes[0]], .solid)
        XCTAssertEqual(frame[buttonNote: XTouchSurfaceProtocol.ButtonZone.solo.notes[0]], .solid)
        XCTAssertEqual(frame[buttonNote: XTouchSurfaceProtocol.ButtonZone.vpotPress.notes[0]], .solid)
        XCTAssertEqual(frame[buttonNote: XTouchSurfaceProtocol.ButtonZone.function.notes[0]], .solid)
        XCTAssertEqual(frame[buttonNote: XTouchSurfaceProtocol.ButtonZone.globalView.notes[0]], .solid)
    }

    func testFaderMirrorLadderZoneBelowThresholdIsBlinkNotOff() {
        // Level 0.3 clears only the lowest rung (.rec at 0.2).
        let faders: [Double] = [0.3] + Array(repeating: 0.5, count: 8)
        let frame = FaderMirrorSurfacePattern().render(elapsed: 0, beat: .idle, params: SurfacePatternParams(), faders: faders)

        XCTAssertEqual(frame[buttonNote: XTouchSurfaceProtocol.ButtonZone.rec.notes[0]], .solid)
        XCTAssertEqual(frame[buttonNote: XTouchSurfaceProtocol.ButtonZone.solo.notes[0]], .blink)
        XCTAssertEqual(frame[buttonNote: XTouchSurfaceProtocol.ButtonZone.globalView.notes[0]], .blink)
    }

    func testFaderMirrorMeterZonesScaleWithAverageLevel() {
        let allZero = [Double](repeating: 0.0, count: 9)
        let allFull = [Double](repeating: 1.0, count: 9)

        let zeroFrame = FaderMirrorSurfacePattern().render(elapsed: 0, beat: .idle, params: SurfacePatternParams(), faders: allZero)
        let fullFrame = FaderMirrorSurfacePattern().render(elapsed: 0, beat: .idle, params: SurfacePatternParams(), faders: allFull)

        let assignNotes = XTouchSurfaceProtocol.ButtonZone.assign.notes
        for note in assignNotes {
            XCTAssertEqual(zeroFrame[buttonNote: note], .blink, "average level 0 should light none of the meter zone")
            XCTAssertEqual(fullFrame[buttonNote: note], .solid, "average level 1 should light all of the meter zone")
        }
    }

    /// "Follow Faders" is the default for the X-Touch's right-hand cluster, where it renders
    /// in isolation — every right-section zone must be touched, or the cluster falls back to
    /// `SurfaceFrame.allOff`'s `.off` and sits dark, breaking the never-fully-dark rule that
    /// the density regression below only checks across the whole surface.
    func testFaderMirrorTouchesEveryRightSectionNote() {
        for level in [0.0, 0.5, 1.0] {
            let faders = [Double](repeating: level, count: XTouchProtocol.faderCount)
            let frame = FaderMirrorSurfacePattern().render(
                elapsed: 0, beat: .idle, params: SurfacePatternParams(), faders: faders
            )
            for note in XTouchSurfaceProtocol.rightSectionButtonNotes {
                XCTAssertNotEqual(frame[buttonNote: note], .off, "note \(note) went dark at fader level \(level)")
            }
        }
    }

    // MARK: - Density regression (Round 5)

    /// Encodes the actual complaint this round fixed: even though every button was
    /// individually working, the show read as "underwhelming" because patterns only ever
    /// lit one small zone against a mostly-dark surface. Every non-Off pattern must keep
    /// the vast majority of the ~105-button surface lit (solid or blink) at all times.
    func testDensePatternsKeepMostButtonsLitAtAllTimes() {
        let densePatterns: [any SurfacePattern] = [
            FullSurfaceSurfacePattern(), ZoneBeatFlashSurfacePattern(), ButtonChaseSurfacePattern(), FaderMirrorSurfacePattern()
        ]
        let totalButtons = XTouchSurfaceProtocol.animatableButtonNotes.count
        let minimumLitFraction = 0.6

        let beats: [BeatClockSnapshot] = [
            BeatClockSnapshot(bpm: 120, phase: 0.0, beatIndex: 0, isLive: true),
            BeatClockSnapshot(bpm: 120, phase: 0.3, beatIndex: 3, isLive: true),
            BeatClockSnapshot(bpm: 120, phase: 0.6, beatIndex: 7, isLive: true),
            BeatClockSnapshot(bpm: 120, phase: 0.95, beatIndex: 12, isLive: true),
            .idle
        ]
        let elapsedValues = [0.0, 2.7, 15.4]
        let faderSets: [[Double]] = [
            [Double](repeating: 0.5, count: 9),
            [Double](repeating: 0.0, count: 9),
            [Double](repeating: 1.0, count: 9)
        ]

        for pattern in densePatterns {
            for beat in beats {
                for elapsed in elapsedValues {
                    for faders in faderSets {
                        let frame = pattern.render(elapsed: elapsed, beat: beat, params: SurfacePatternParams(), faders: faders)
                        let litCount = frame.buttons.filter { $0 != .off }.count
                        let fraction = Double(litCount) / Double(totalButtons)
                        XCTAssertGreaterThanOrEqual(
                            fraction, minimumLitFraction,
                            "\(type(of: pattern).id) only lit \(Int(fraction * 100))% of buttons at phase \(beat.phase), elapsed \(elapsed)"
                        )
                    }
                }
            }
        }
    }
}
