import Foundation

/// A snapshot of the shared beat clock at a point in time. Both the fader pattern engine
/// and the Launchpad pattern engine read from the same `BeatClock` instance (see
/// `BeatClock.swift`) so fader movement and pixel-art animation stay locked to each other
/// and to the music.
public struct BeatClockSnapshot: Equatable {
    /// Current smoothed tempo estimate, in beats per minute.
    public let bpm: Double
    /// Fraction of the current beat elapsed, in 0..<1 (0 = right on the beat).
    public let phase: Double
    /// Monotonically increasing count of beats since the clock started/was reset.
    public let beatIndex: Int
    /// False when the clock has no recent onset data and is free-running on a stale or
    /// manually-set BPM rather than actively tracking the music.
    public let isLive: Bool

    public init(bpm: Double, phase: Double, beatIndex: Int, isLive: Bool) {
        self.bpm = bpm
        self.phase = phase
        self.beatIndex = beatIndex
        self.isLive = isLive
    }

    /// A neutral default snapshot (120 BPM, not live) for free-running/manual mode and tests.
    public static let idle = BeatClockSnapshot(bpm: 120, phase: 0, beatIndex: 0, isLive: false)
}
