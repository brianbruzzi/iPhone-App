import Foundation

public struct FaderPatternParams: Equatable {
    /// Meaning depends on the pattern: wave = cycles/sec, beatPulse = decay speed multiplier,
    /// beatChase = unused (chase speed is dictated by the beat itself).
    public var speed: Double
    /// 0...1, how far the pattern swings around `baseLevel`.
    public var amplitude: Double
    /// 0...1, the rest/center fader position.
    public var baseLevel: Double

    public init(speed: Double = 1.0, amplitude: Double = 1.0, baseLevel: Double = 0.5) {
        self.speed = speed
        self.amplitude = amplitude
        self.baseLevel = baseLevel
    }
}

/// Generates target positions for all 9 X-Touch faders on every animation tick. Pure
/// function of elapsed time + the shared beat clock — no MIDI/hardware dependency, so
/// every pattern is deterministically testable.
public protocol FaderPattern {
    static var id: String { get }
    static var displayName: String { get }

    /// Returns exactly `XTouchProtocol.faderCount` values (index 0-7 = channel strips,
    /// index 8 = master). Each is either a target position in 0...1, or `.nan` meaning
    /// "send nothing for this fader this tick" — used by `ManualOffFaderPattern` to
    /// release all faders, and by `PatternEngine` to skip faders the user is touching.
    func faderValues(elapsed: TimeInterval, beat: BeatClockSnapshot, params: FaderPatternParams) -> [Double]
}

/// Sine sweep across all 9 faders, each offset in phase so the motion visibly travels
/// across the bank rather than every fader moving in lockstep.
public struct WaveFaderPattern: FaderPattern {
    public static let id = "wave"
    public static let displayName = "Wave"

    public init() {}

    public func faderValues(elapsed: TimeInterval, beat: BeatClockSnapshot, params: FaderPatternParams) -> [Double] {
        (0..<XTouchProtocol.faderCount).map { index in
            let phaseOffset = Double(index) / Double(XTouchProtocol.faderCount) * 2 * .pi
            let angle = 2 * .pi * params.speed * elapsed + phaseOffset
            let value = params.baseLevel + params.amplitude * 0.5 * sin(angle)
            return min(max(value, 0), 1)
        }
    }
}

/// All faders jump together on each beat and decay back toward `baseLevel` — a unison pulse.
public struct BeatPulseFaderPattern: FaderPattern {
    public static let id = "beatPulse"
    public static let displayName = "Beat Pulse"

    public init() {}

    public func faderValues(elapsed: TimeInterval, beat: BeatClockSnapshot, params: FaderPatternParams) -> [Double] {
        let beatPeriod = beat.bpm > 0 ? 60.0 / beat.bpm : 0.5
        let timeSinceBeat = beat.phase * beatPeriod
        // Higher `speed` = snappier pulse that decays before the next beat; lower = a
        // longer glow that bleeds into it.
        let decayRate = max(params.speed, 0.01) * 6.0
        let envelope = exp(-decayRate * timeSinceBeat)
        let value = params.baseLevel + params.amplitude * 0.5 * envelope
        let clamped = min(max(value, 0), 1)
        return Array(repeating: clamped, count: XTouchProtocol.faderCount)
    }
}

/// One fader raised at a time, advancing to the next on every beat.
public struct BeatChaseFaderPattern: FaderPattern {
    public static let id = "beatChase"
    public static let displayName = "Beat Chase"

    public init() {}

    public func faderValues(elapsed: TimeInterval, beat: BeatClockSnapshot, params: FaderPatternParams) -> [Double] {
        let count = XTouchProtocol.faderCount
        let activeIndex = ((beat.beatIndex % count) + count) % count
        return (0..<count).map { index in
            let value = index == activeIndex
                ? params.baseLevel + params.amplitude * 0.5
                : params.baseLevel - params.amplitude * 0.5
            return min(max(value, 0), 1)
        }
    }
}

/// Sends nothing — releases all faders to manual/DAW control.
public struct ManualOffFaderPattern: FaderPattern {
    public static let id = "manualOff"
    public static let displayName = "Off (Manual Control)"

    public init() {}

    public func faderValues(elapsed: TimeInterval, beat: BeatClockSnapshot, params: FaderPatternParams) -> [Double] {
        Array(repeating: Double.nan, count: XTouchProtocol.faderCount)
    }
}

/// Convenience registry of all built-in fader patterns, for UI pickers.
public enum FaderPatterns {
    public static let all: [any FaderPattern] = [
        WaveFaderPattern(),
        BeatPulseFaderPattern(),
        BeatChaseFaderPattern(),
        ManualOffFaderPattern()
    ]
}
