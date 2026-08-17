import Foundation

/// Turns a stream of onset timestamps (from `SpectralFluxOnsetDetector`) into a smoothed
/// BPM estimate and a predictable beat phase, exposed as `BeatClockSnapshot`. A single
/// shared `BeatClock` instance is read by both the fader pattern engine and the Launchpad
/// pattern engine, so their animations stay locked to each other and to the music.
public final class BeatClock {
    public private(set) var bpm: Double

    private var lastOnsetTime: TimeInterval?
    private var lastBeatAnchorTime: TimeInterval = 0
    private var beatIndex: Int = 0
    private var hasLiveData = false

    private let minBPM: Double
    private let maxBPM: Double
    /// 0...1: how much weight each new inter-onset-interval candidate gets against the
    /// running BPM estimate. Higher = snaps to tempo changes faster but jitters more.
    private let smoothing: Double

    public init(initialBPM: Double = 120, minBPM: Double = 60, maxBPM: Double = 200, smoothing: Double = 0.25) {
        self.bpm = initialBPM
        self.minBPM = minBPM
        self.maxBPM = maxBPM
        self.smoothing = smoothing
    }

    /// Feeds a detected onset at `time` (same time base as `snapshot(now:)`). Updates the
    /// smoothed BPM estimate from the interval since the previous onset (with octave-error
    /// folding into the plausible BPM range) and re-anchors beat phase to this onset.
    public func ingest(onsetAt time: TimeInterval) {
        defer {
            lastOnsetTime = time
            lastBeatAnchorTime = time
            beatIndex += 1
            hasLiveData = true
        }

        guard let last = lastOnsetTime else { return }
        let interval = time - last
        guard interval > 0, let candidateBPM = BeatClock.foldedBPM(forInterval: interval, minBPM: minBPM, maxBPM: maxBPM) else {
            return
        }
        bpm = bpm * (1 - smoothing) + candidateBPM * smoothing
    }

    /// Directly sets the tempo (e.g. from a UI "manual BPM" field when no track is
    /// playing) and re-anchors phase to `now`. Marks the clock as not live, since this
    /// tempo isn't derived from actual onsets.
    public func setManualBPM(_ newBPM: Double, now: TimeInterval) {
        bpm = min(max(newBPM, minBPM), maxBPM)
        lastBeatAnchorTime = now
        hasLiveData = false
    }

    /// Interpolates the current beat phase/index from the last known onset/anchor, given
    /// the current time `now` (same time base as `ingest(onsetAt:)`).
    public func snapshot(now: TimeInterval) -> BeatClockSnapshot {
        let beatPeriod = bpm > 0 ? 60.0 / bpm : 0.5
        let elapsedSinceAnchor = max(0, now - lastBeatAnchorTime)
        let beatsSinceAnchor = Int(elapsedSinceAnchor / beatPeriod)
        let phase = (elapsedSinceAnchor.truncatingRemainder(dividingBy: beatPeriod)) / beatPeriod

        // Once too much silence has passed since the last real onset, stop claiming to be
        // "live" — patterns can use this to fall back to a free-running/idle look.
        let stalenessLimit = beatPeriod * 4
        let isLive = hasLiveData && elapsedSinceAnchor < stalenessLimit

        return BeatClockSnapshot(bpm: bpm, phase: phase, beatIndex: beatIndex + beatsSinceAnchor, isLive: isLive)
    }

    /// Converts an inter-onset interval into a BPM candidate, folding octave errors
    /// (interval implying roughly half or double the plausible tempo) into `[minBPM,
    /// maxBPM]`. Returns nil if no amount of octave-folding brings it into range.
    private static func foldedBPM(forInterval interval: TimeInterval, minBPM: Double, maxBPM: Double) -> Double? {
        guard interval > 0 else { return nil }
        var candidate = 60.0 / interval

        var guardCount = 0
        while candidate < minBPM, guardCount < 8 {
            candidate *= 2
            guardCount += 1
        }
        guardCount = 0
        while candidate > maxBPM, guardCount < 8 {
            candidate /= 2
            guardCount += 1
        }

        guard (minBPM...maxBPM).contains(candidate) else { return nil }
        return candidate
    }
}
