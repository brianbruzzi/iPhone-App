import Foundation

/// Turns a series of button taps into a BPM estimate, for setting the beat clock's tempo
/// by feel instead of typing a number. Pure value type with the caller supplying
/// timestamps, so it's deterministic and fully testable — same design rule as the rest of
/// this package.
public struct TapTempoTracker {
    /// Taps further apart than this start a fresh run rather than continuing the old one —
    /// 2s is a 30 BPM interval, slower than any tempo worth tapping.
    public static let resetGap: TimeInterval = 2.0
    /// Only the most recent taps count, so the estimate tracks a drifting tapper instead
    /// of averaging against stale history.
    public static let maxTaps = 8
    public static let bpmRange: ClosedRange<Double> = 30...300

    private var tapTimes: [TimeInterval] = []

    public init() {}

    /// Registers a tap at `time` (any monotonic clock, seconds) and returns the current
    /// BPM estimate, or nil until there are at least two taps in the active run.
    /// The estimate is the mean interval across the run, clamped to `bpmRange`.
    public mutating func registerTap(at time: TimeInterval) -> Double? {
        if let last = tapTimes.last, time - last > Self.resetGap || time <= last {
            tapTimes.removeAll()
        }
        tapTimes.append(time)
        if tapTimes.count > Self.maxTaps {
            tapTimes.removeFirst(tapTimes.count - Self.maxTaps)
        }

        guard tapTimes.count >= 2, let first = tapTimes.first, let last = tapTimes.last else {
            return nil
        }
        let meanInterval = (last - first) / Double(tapTimes.count - 1)
        guard meanInterval > 0 else { return nil }
        let bpm = 60.0 / meanInterval
        return min(max(bpm, Self.bpmRange.lowerBound), Self.bpmRange.upperBound)
    }
}
