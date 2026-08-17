import Foundation

/// A pause-aware elapsed-time clock. Accumulates run-time across pause/resume cycles
/// rather than anchoring to a single start instant, so resuming never produces a jump in
/// the `elapsed` value patterns are driven by — the animation picks up exactly where it
/// left off, whatever real-world time passed while paused.
public struct TransportClock: Equatable, Sendable {
    public private(set) var isRunning: Bool

    private var accumulated: TimeInterval
    private var runningSince: TimeInterval?

    /// Starts running immediately; `elapsed(at: hostTime)` is 0.
    public init(startedAt hostTime: TimeInterval) {
        isRunning = true
        accumulated = 0
        runningSince = hostTime
    }

    /// Stops advancing `elapsed`. Idempotent — pausing an already-paused clock is a no-op.
    public mutating func pause(at hostTime: TimeInterval) {
        guard isRunning, let since = runningSince else { return }
        accumulated += max(0, hostTime - since)
        runningSince = nil
        isRunning = false
    }

    /// Resumes advancing `elapsed` from wherever it left off. Idempotent — resuming an
    /// already-running clock is a no-op.
    public mutating func resume(at hostTime: TimeInterval) {
        guard !isRunning else { return }
        runningSince = hostTime
        isRunning = true
    }

    /// Seconds of run-time accumulated so far. Never negative: a `hostTime` earlier than
    /// this run's start (or resume) point floors at the accumulated total rather than
    /// going below it. This is a pure query with no memory of prior calls, so it assumes
    /// `hostTime` comes from a monotonic clock across a real call sequence (as
    /// `mach_absolute_time`-derived host time is) — it does not itself guard against a
    /// later call passing an earlier `hostTime` than a previous call did.
    public func elapsed(at hostTime: TimeInterval) -> TimeInterval {
        guard isRunning, let since = runningSince else { return accumulated }
        return accumulated + max(0, hostTime - since)
    }
}
