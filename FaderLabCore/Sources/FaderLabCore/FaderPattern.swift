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

/// A single "comet" scans back and forth across the 9 faders, Knight-Rider style.
public struct SweepFaderPattern: FaderPattern {
    public static let id = "sweep"
    public static let displayName = "Sweep"

    public init() {}

    public func faderValues(elapsed: TimeInterval, beat: BeatClockSnapshot, params: FaderPatternParams) -> [Double] {
        let count = XTouchProtocol.faderCount
        let speed = max(params.speed, 0.01)
        let scanPosition = SweepFaderPattern.triangleWave(elapsed * speed * 0.5) * Double(count - 1)
        let restLevel = params.baseLevel - params.amplitude * 0.5

        return (0..<count).map { index in
            let distance = abs(Double(index) - scanPosition)
            let falloff = max(0, 1 - distance / 1.5)
            let value = restLevel + params.amplitude * falloff
            return min(max(value, 0), 1)
        }
    }

    /// Triangle wave 0...1...0 with period 2 (in the same time units as `t`).
    static func triangleWave(_ t: Double) -> Double {
        let cyclePosition = t.truncatingRemainder(dividingBy: 2)
        let normalized = cyclePosition < 0 ? cyclePosition + 2 : cyclePosition
        return normalized <= 1 ? normalized : 2 - normalized
    }
}

/// Each fader wanders independently in a chaotic-looking but fully deterministic way
/// (combined sine waves at incommensurate frequencies per fader, not true randomness —
/// same `elapsed` always produces the same output, which keeps this pattern testable).
public struct RandomJitterFaderPattern: FaderPattern {
    public static let id = "randomJitter"
    public static let displayName = "Random Jitter"

    public init() {}

    public func faderValues(elapsed: TimeInterval, beat: BeatClockSnapshot, params: FaderPatternParams) -> [Double] {
        let speed = max(params.speed, 0.01)
        return (0..<XTouchProtocol.faderCount).map { index in
            let seed = Double(index) * 12.9898
            let angle1 = elapsed * speed * (1.3 + Double(index) * 0.37) + seed
            let angle2 = elapsed * speed * (2.7 + Double(index) * 0.19) + seed * 1.7
            let noise = (sin(angle1) + sin(angle2 * 1.618)) / 2 // -1...1, looks chaotic
            let value = params.baseLevel + params.amplitude * 0.5 * noise
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
        SweepFaderPattern(),
        RandomJitterFaderPattern(),
        ManualOffFaderPattern()
    ]
}
