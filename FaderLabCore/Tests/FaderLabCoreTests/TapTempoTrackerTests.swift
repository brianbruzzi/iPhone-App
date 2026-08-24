import XCTest
@testable import FaderLabCore

final class TapTempoTrackerTests: XCTestCase {

    func testSingleTapReturnsNil() {
        var tracker = TapTempoTracker()
        XCTAssertNil(tracker.registerTap(at: 10.0))
    }

    func testSteadyTapsAt120BPM() {
        var tracker = TapTempoTracker()
        var bpm: Double?
        for i in 0..<4 {
            bpm = tracker.registerTap(at: Double(i) * 0.5) // 0.5s apart = 120 BPM
        }
        XCTAssertEqual(bpm ?? 0, 120, accuracy: 0.001)
    }

    func testGapLongerThanResetStartsAFreshRun() {
        var tracker = TapTempoTracker()
        _ = tracker.registerTap(at: 0.0)
        _ = tracker.registerTap(at: 0.5)
        // 5s gap — old run must not pollute the new one's estimate.
        XCTAssertNil(tracker.registerTap(at: 5.5), "first tap of a fresh run has no interval yet")
        let bpm = tracker.registerTap(at: 6.5) // 1.0s apart = 60 BPM
        XCTAssertEqual(bpm ?? 0, 60, accuracy: 0.001)
    }

    func testOnlyRecentTapsCount() {
        var tracker = TapTempoTracker()
        var bpm: Double?
        // 12 taps, all 0.5s apart; only the last 8 are kept, but the tempo is constant so
        // the estimate must still be exactly 120 (this asserts trimming doesn't corrupt).
        for i in 0..<12 {
            bpm = tracker.registerTap(at: Double(i) * 0.5)
        }
        XCTAssertEqual(bpm ?? 0, 120, accuracy: 0.001)
    }

    func testBPMClampsToSaneRange() {
        var fast = TapTempoTracker()
        _ = fast.registerTap(at: 0.00)
        let tooFast = fast.registerTap(at: 0.05) // 1200 BPM raw
        XCTAssertEqual(tooFast, TapTempoTracker.bpmRange.upperBound)

        var slow = TapTempoTracker()
        _ = slow.registerTap(at: 0.0)
        let tooSlow = slow.registerTap(at: 1.99) // ~30.15 BPM, just inside the reset gap
        XCTAssertEqual(tooSlow ?? 0, 60.0 / 1.99, accuracy: 0.001)
    }

    func testNonMonotonicTimeResetsInsteadOfProducingGarbage() {
        var tracker = TapTempoTracker()
        _ = tracker.registerTap(at: 10.0)
        XCTAssertNil(tracker.registerTap(at: 9.0), "time going backwards starts a fresh run")
    }
}
