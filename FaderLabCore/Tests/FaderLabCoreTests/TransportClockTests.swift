import XCTest
@testable import FaderLabCore

final class TransportClockTests: XCTestCase {

    func testElapsedAdvancesWhileRunning() {
        let clock = TransportClock(startedAt: 100)
        XCTAssertEqual(clock.elapsed(at: 100), 0)
        XCTAssertEqual(clock.elapsed(at: 105), 5)
        XCTAssertEqual(clock.elapsed(at: 110.5), 10.5)
    }

    func testPauseFreezesElapsed() {
        var clock = TransportClock(startedAt: 0)
        clock.pause(at: 5)
        XCTAssertEqual(clock.elapsed(at: 5), 5)
        // Time passing while paused must not move elapsed.
        XCTAssertEqual(clock.elapsed(at: 105), 5)
        XCTAssertEqual(clock.elapsed(at: 1000), 5)
    }

    func testResumeContinuesWithoutJump() {
        // Pause at t=5 (elapsed=5), let 100s of real time pass, resume, advance 1s more —
        // elapsed should read 6, not 101 and not reset to 0.
        var clock = TransportClock(startedAt: 0)
        clock.pause(at: 5)
        clock.resume(at: 105)
        XCTAssertEqual(clock.elapsed(at: 106), 6)
    }

    func testMultiplePauseResumeCycles() {
        var clock = TransportClock(startedAt: 0)
        XCTAssertEqual(clock.elapsed(at: 3), 3)
        clock.pause(at: 3)
        clock.resume(at: 50)
        XCTAssertEqual(clock.elapsed(at: 52), 5)
        clock.pause(at: 52)
        clock.resume(at: 200)
        XCTAssertEqual(clock.elapsed(at: 204), 9)
    }

    func testDoublePauseIsIdempotent() {
        var clock = TransportClock(startedAt: 0)
        clock.pause(at: 5)
        clock.pause(at: 50) // should not add the 45s gap
        XCTAssertEqual(clock.elapsed(at: 100), 5)
    }

    func testDoubleResumeIsIdempotent() {
        var clock = TransportClock(startedAt: 0)
        clock.resume(at: 5) // already running; must not re-anchor
        XCTAssertEqual(clock.elapsed(at: 10), 10)
    }

    func testIsRunningReflectsState() {
        var clock = TransportClock(startedAt: 0)
        XCTAssertTrue(clock.isRunning)
        clock.pause(at: 1)
        XCTAssertFalse(clock.isRunning)
        clock.resume(at: 2)
        XCTAssertTrue(clock.isRunning)
    }

    func testHostTimeBeforeStartFloorsAtZeroRatherThanGoingNegative() {
        let clock = TransportClock(startedAt: 100)
        // A hostTime earlier than the start should never produce negative elapsed.
        XCTAssertEqual(clock.elapsed(at: 50), 0)
    }

    func testHostTimeBeforeResumePointFloorsAtAccumulatedTotal() {
        var clock = TransportClock(startedAt: 0)
        clock.pause(at: 5)
        clock.resume(at: 100)
        // A hostTime earlier than the resume point should floor at the 5s accumulated
        // before the pause, not go below it or go negative.
        XCTAssertEqual(clock.elapsed(at: 50), 5)
    }
}
