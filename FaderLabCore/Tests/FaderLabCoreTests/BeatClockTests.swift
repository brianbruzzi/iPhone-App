import XCTest
@testable import FaderLabCore

final class BeatClockTests: XCTestCase {

    func testConvergesToKnownBPMFromClickTrain() {
        let clock = BeatClock(initialBPM: 100, smoothing: 0.5)
        // 120 BPM == 0.5s per beat.
        var t = 0.0
        for _ in 0..<10 {
            clock.ingest(onsetAt: t)
            t += 0.5
        }
        XCTAssertEqual(clock.bpm, 120, accuracy: 1.0)
    }

    func testSnapshotPhaseAdvancesBetweenOnsets() {
        let clock = BeatClock(initialBPM: 120)
        clock.ingest(onsetAt: 0)
        // 0.5s beat period at 120 BPM.
        XCTAssertEqual(clock.snapshot(now: 0.1).phase, 0.2, accuracy: 0.05)
        XCTAssertEqual(clock.snapshot(now: 0.4).phase, 0.8, accuracy: 0.05)
    }

    func testManualBPMOverridesAndMarksNotLive() {
        let clock = BeatClock(initialBPM: 120)
        clock.setManualBPM(90, now: 0)
        let snapshot = clock.snapshot(now: 0)
        XCTAssertEqual(snapshot.bpm, 90, accuracy: 1e-9)
        XCTAssertFalse(snapshot.isLive)
    }

    func testManualBPMIsClampedToRange() {
        let clock = BeatClock(initialBPM: 120, minBPM: 60, maxBPM: 200)
        clock.setManualBPM(500, now: 0)
        XCTAssertEqual(clock.bpm, 200, accuracy: 1e-9)
        clock.setManualBPM(1, now: 0)
        XCTAssertEqual(clock.bpm, 60, accuracy: 1e-9)
    }

    func testBeatIndexIncrementsPerIngestedOnset() {
        let clock = BeatClock(initialBPM: 120, smoothing: 1.0)
        clock.ingest(onsetAt: 0)
        clock.ingest(onsetAt: 0.5)
        clock.ingest(onsetAt: 1.0)
        XCTAssertEqual(clock.snapshot(now: 1.0).beatIndex, 3)
    }

    func testStaleClockReportsNotLive() {
        let clock = BeatClock(initialBPM: 120)
        clock.ingest(onsetAt: 0)
        // Long silence, far beyond a few beat periods.
        XCTAssertFalse(clock.snapshot(now: 10.0).isLive)
    }

    func testFreshOnsetReportsLive() {
        let clock = BeatClock(initialBPM: 120)
        clock.ingest(onsetAt: 0)
        XCTAssertTrue(clock.snapshot(now: 0.1).isLive)
    }

    func testOctaveErrorFoldingKeepsBPMInRange() {
        let clock = BeatClock(initialBPM: 120, minBPM: 60, maxBPM: 200, smoothing: 1.0)
        // A 1.5s interval implies 40 BPM, which is below minBPM and should fold up to 80.
        clock.ingest(onsetAt: 0)
        clock.ingest(onsetAt: 1.5)
        XCTAssertEqual(clock.bpm, 80, accuracy: 1.0)
    }
}
