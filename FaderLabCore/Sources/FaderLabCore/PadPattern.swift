import Foundation

public struct PadPatternParams: Equatable {
    public var speed: Double
    /// 0...1, rotates every pattern's hue wheel — lets the same pattern be recolored.
    public var hueShift: Double
    /// 0...1, overall brightness multiplier.
    public var brightness: Double
    /// Live audio level (RMS/peak, 0...1), computed from the same tap buffer used for
    /// onset detection. Only consumed by audio-level-driven patterns (e.g. VU columns) —
    /// other patterns ignore it, which is simpler than splitting `PadPattern` into
    /// beat-only vs. audio-only protocol variants.
    public var audioLevel: Double

    public init(speed: Double = 1.0, hueShift: Double = 0, brightness: Double = 1.0, audioLevel: Double = 0) {
        self.speed = speed
        self.hueShift = hueShift
        self.brightness = brightness
        self.audioLevel = audioLevel
    }
}

/// Renders a full 8x8 pixel-art frame on every animation tick. Pure function of elapsed
/// time + the shared beat clock — no MIDI/hardware dependency, so every pattern is
/// deterministically testable.
public protocol PadPattern {
    static var id: String { get }
    static var displayName: String { get }

    func render(elapsed: TimeInterval, beat: BeatClockSnapshot, params: PadPatternParams) -> PixelGrid
}

/// Classic demoscene plasma: three overlapping sine fields (horizontal, vertical, radial)
/// summed and mapped to hue.
public struct PlasmaWavePattern: PadPattern {
    public static let id = "plasmaWave"
    public static let displayName = "Plasma Wave"

    public init() {}

    public func render(elapsed: TimeInterval, beat: BeatClockSnapshot, params: PadPatternParams) -> PixelGrid {
        let t = elapsed * params.speed
        var grid = PixelGrid.allBlack
        let center = 3.5
        for y in 0..<8 {
            for x in 0..<8 {
                let fx = Double(x)
                let fy = Double(y)
                let horizontal = sin(fx * 0.9 + t)
                let vertical = sin(fy * 0.9 + t * 1.3)
                let dx = fx - center
                let dy = fy - center
                let radial = sin(sqrt(dx * dx + dy * dy) * 1.2 - t * 1.7)
                let sum = (horizontal + vertical + radial) / 3.0 // -1...1
                let hue = (sum + 1) / 2 + params.hueShift
                grid[x, y] = RGBColor(hue: hue, saturation: 1, value: params.brightness)
            }
        }
        return grid
    }
}

/// A rainbow hue gradient sweeping diagonally across the grid over time.
public struct RainbowChasePattern: PadPattern {
    public static let id = "rainbowChase"
    public static let displayName = "Rainbow Chase"

    public init() {}

    public func render(elapsed: TimeInterval, beat: BeatClockSnapshot, params: PadPatternParams) -> PixelGrid {
        let t = elapsed * params.speed
        var grid = PixelGrid.allBlack
        for y in 0..<8 {
            for x in 0..<8 {
                let diagonal = Double(x + y) / 14.0 // 0...1 across the diagonal
                let hue = diagonal + t * 0.15 + params.hueShift
                grid[x, y] = RGBColor(hue: hue, saturation: 1, value: params.brightness)
            }
        }
        return grid
    }
}

/// A ring expands outward from the center pad each time `beat.beatIndex` advances, fading
/// out as it grows.
public struct BeatRipplePattern: PadPattern {
    public static let id = "beatRipple"
    public static let displayName = "Beat Ripple"

    public init() {}

    public func render(elapsed: TimeInterval, beat: BeatClockSnapshot, params: PadPatternParams) -> PixelGrid {
        let beatPeriod = beat.bpm > 0 ? 60.0 / beat.bpm : 0.5
        let age = beat.phase * beatPeriod
        let speed = max(params.speed, 0.01)
        let maxRadius = 6.0
        let expansionSpeed = speed * maxRadius * 2 // reaches the edge partway through the beat
        let radius = age * expansionSpeed
        let ringWidth = 1.2
        let fade = max(0, 1 - age * speed * 2)

        var grid = PixelGrid.allBlack
        guard fade > 0 else { return grid }

        let center = 3.5
        for y in 0..<8 {
            for x in 0..<8 {
                let dx = Double(x) - center
                let dy = Double(y) - center
                let distance = sqrt(dx * dx + dy * dy)
                let ringDistance = abs(distance - radius)
                guard ringDistance < ringWidth else { continue }
                let ringIntensity = (1 - ringDistance / ringWidth) * fade
                guard ringIntensity > 0 else { continue }
                grid[x, y] = RGBColor(hue: params.hueShift, saturation: 1, value: params.brightness * ringIntensity)
            }
        }
        return grid
    }
}

/// Treats each of the 8 columns as a VU-meter bar driven by the live audio level, colored
/// green (quiet) -> yellow -> red (loud) from bottom to top.
public struct VUMeterColumnsPattern: PadPattern {
    public static let id = "vuColumns"
    public static let displayName = "VU Columns"

    public init() {}

    public func render(elapsed: TimeInterval, beat: BeatClockSnapshot, params: PadPatternParams) -> PixelGrid {
        var grid = PixelGrid.allBlack
        let level = min(max(params.audioLevel, 0), 1)

        for x in 0..<8 {
            let wobble = 0.75 + 0.25 * sin(Double(x) * 1.3 + elapsed * params.speed * 4)
            let columnLevel = min(max(level * wobble, 0), 1)
            let litRows = Int((columnLevel * 8).rounded(.up))
            guard litRows > 0 else { continue }
            for rowFromBottom in 0..<litRows {
                let y = 7 - rowFromBottom
                let heightFraction = Double(rowFromBottom + 1) / 8.0
                let hue = hue(forHeightFraction: heightFraction) + params.hueShift
                grid[x, y] = RGBColor(hue: hue, saturation: 1, value: params.brightness)
            }
        }
        return grid
    }

    /// Classic VU meter coloring: green low, yellow mid, red high.
    private func hue(forHeightFraction heightFraction: Double) -> Double {
        if heightFraction < 0.7 {
            return 0.33 - (0.17 * (heightFraction / 0.7)) // green -> yellow
        } else {
            let t = (heightFraction - 0.7) / 0.3
            return 0.16 - (0.16 * t) // yellow -> red
        }
    }
}

/// Pads twinkle on and off at varying brightness, like starlight. Deterministic (combined
/// sine waves per pad, not true randomness) so it's reproducible and testable.
public struct SparklePattern: PadPattern {
    public static let id = "sparkle"
    public static let displayName = "Sparkle"

    public init() {}

    public func render(elapsed: TimeInterval, beat: BeatClockSnapshot, params: PadPatternParams) -> PixelGrid {
        var grid = PixelGrid.allBlack
        let speed = max(params.speed, 0.01)
        for y in 0..<8 {
            for x in 0..<8 {
                let seed = Double(x) * 7.13 + Double(y) * 3.71
                let phase = elapsed * speed * 2.2 + seed
                let twinkle = (sin(phase) + sin(phase * 1.41 + seed)) / 2 // -1...1
                // Only the upper part of the cycle lights up, giving sparse twinkling
                // rather than every pad glowing all the time.
                guard twinkle > 0.55 else { continue }
                let intensity = (twinkle - 0.55) / 0.45
                grid[x, y] = RGBColor(hue: params.hueShift, saturation: 0.15, value: params.brightness * intensity)
            }
        }
        return grid
    }
}

/// A ball bounces around the grid, DVD-screensaver style, leaving a soft glow.
public struct BouncingBallPattern: PadPattern {
    public static let id = "bouncingBall"
    public static let displayName = "Bouncing Ball"

    public init() {}

    public func render(elapsed: TimeInterval, beat: BeatClockSnapshot, params: PadPatternParams) -> PixelGrid {
        let speed = max(params.speed, 0.01)
        let ballX = BouncingBallPattern.triangleWave(elapsed * speed * 0.9) * 7
        let ballY = BouncingBallPattern.triangleWave(elapsed * speed * 1.3 + 0.37) * 7

        var grid = PixelGrid.allBlack
        for y in 0..<8 {
            for x in 0..<8 {
                let dx = Double(x) - ballX
                let dy = Double(y) - ballY
                let distance = sqrt(dx * dx + dy * dy)
                let intensity = max(0, 1 - distance / 1.4)
                guard intensity > 0 else { continue }
                grid[x, y] = RGBColor(hue: params.hueShift, saturation: 1, value: params.brightness * intensity)
            }
        }
        return grid
    }

    /// Triangle wave 0...1...0 with period 2 (in the same time units as `t`).
    static func triangleWave(_ t: Double) -> Double {
        let cyclePosition = t.truncatingRemainder(dividingBy: 2)
        let normalized = cyclePosition < 0 ? cyclePosition + 2 : cyclePosition
        return normalized <= 1 ? normalized : 2 - normalized
    }
}

/// Convenience registry of all built-in pad patterns, for UI pickers.
public enum PadPatterns {
    public static let all: [any PadPattern] = [
        PlasmaWavePattern(),
        RainbowChasePattern(),
        BeatRipplePattern(),
        VUMeterColumnsPattern(),
        SparklePattern(),
        BouncingBallPattern()
    ]
}
