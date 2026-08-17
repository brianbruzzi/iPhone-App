import Foundation

public struct SurfacePatternParams: Equatable, Sendable {
    /// Meaning depends on the pattern: animation rate multiplier for time-driven motion.
    public var speed: Double
    /// 0...1: how much of the beat/cycle stays lit, or how strongly a pattern reacts.
    public var intensity: Double

    public init(speed: Double = 1.0, intensity: Double = 1.0) {
        self.speed = speed
        self.intensity = intensity
    }
}

/// Renders a full X-Touch surface lighting frame (button LEDs, encoder rings, scribble
/// strips) on every animation tick. Pure function of elapsed time + the shared beat clock
/// — no MIDI/hardware dependency, so every pattern is deterministically testable.
public protocol SurfacePattern {
    static var id: String { get }
    static var displayName: String { get }

    /// `faders` is `PatternEngine.lastKnownFaderValues`: the 9 most recent finite fader
    /// positions (0...1, channel strips 0-7 then master), for patterns that mirror what
    /// the faders are doing. Always finite; may be a different length than 9 if called
    /// directly (e.g. in tests) — implementations should tolerate that rather than crash.
    func render(elapsed: TimeInterval, beat: BeatClockSnapshot, params: SurfacePatternParams, faders: [Double]) -> SurfaceFrame
}

/// One button-row zone lights solid at each beat onset and cuts off partway through the
/// beat (cycling REC -> SOLO -> MUTE -> SELECT), Play blinks in time, the encoder rings
/// pulse outward from center, and the scribble strips step through a color per bar.
public struct ZoneBeatFlashSurfacePattern: SurfacePattern {
    public static let id = "beatFlash"
    public static let displayName = "Beat Flash"

    public init() {}

    private static let zones: [XTouchSurfaceProtocol.ButtonZone] = [
        .rec, .solo, .mute, .select, .assign, .automation, .globalView, .cursor
    ]
    private static let playButtonNote: UInt8 = XTouchSurfaceProtocol.ButtonZone.transport.notes[3]
    private static let brandingTexts: [ScribbleText] = [
        ScribbleText(upper: "FADER", lower: "LAB"),
        ScribbleText(upper: "FADER", lower: "LAB"),
        ScribbleText(upper: "FADER", lower: "LAB"),
        ScribbleText(upper: "FADER", lower: "LAB"),
        ScribbleText(upper: "BEAT", lower: "FLASH"),
        ScribbleText(upper: "BEAT", lower: "FLASH"),
        ScribbleText(upper: "BEAT", lower: "FLASH"),
        ScribbleText(upper: "BEAT", lower: "FLASH")
    ]

    public func render(elapsed: TimeInterval, beat: BeatClockSnapshot, params: SurfacePatternParams, faders: [Double]) -> SurfaceFrame {
        var frame = SurfaceFrame.allOff

        let zoneCount = Self.zones.count
        let zoneIndex = ((beat.beatIndex % zoneCount) + zoneCount) % zoneCount
        let lit = beat.phase <= max(0.01, params.intensity)
        frame.fill(Self.zones[zoneIndex], with: lit ? .solid : .off)
        frame[buttonNote: Self.playButtonNote] = .blink

        let ringPosition = Int(((1 - beat.phase) * 11).rounded())
        let ringDisplay = XTouchSurfaceProtocol.RingDisplay(mode: .spread, position: ringPosition, centerLED: lit)
        frame.rings = Array(repeating: ringDisplay, count: XTouchSurfaceProtocol.stripCount)

        let barIndex = beat.beatIndex / 4
        let colorRaw = UInt8(((barIndex % 7) + 7) % 7 + 1) // 1...7, skips black
        let color = XTouchSurfaceProtocol.ScribbleColor(rawValue: colorRaw) ?? .white
        frame.scribbleColors = Array(repeating: color, count: XTouchSurfaceProtocol.stripCount)
        frame.scribbleTexts = Self.brandingTexts

        return frame
    }
}

/// A lit column sweeps across all 8 strips' buttons in lockstep, F-keys and the encoder
/// rings chase along with it, and the scribble strips cycle a moving rainbow.
public struct ButtonChaseSurfacePattern: SurfacePattern {
    public static let id = "chase"
    public static let displayName = "Chase"

    public init() {}

    // Direct `zone.notes[column]` indexing below requires each zone to have at least
    // `stripCount` (8) notes — every zone here does. Zones with fewer notes (e.g.
    // `.transport`, `.assign`, `.cursor`) use modulo-wrapped indexing instead, below.
    private static let columnZones: [XTouchSurfaceProtocol.ButtonZone] = [
        .rec, .solo, .mute, .select, .vpotPress, .globalView
    ]

    public func render(elapsed: TimeInterval, beat: BeatClockSnapshot, params: SurfacePatternParams, faders: [Double]) -> SurfaceFrame {
        var frame = SurfaceFrame.allOff
        let speed = max(params.speed, 0.01)
        let stripCount = XTouchSurfaceProtocol.stripCount

        let column: Int
        if beat.isLive {
            column = ((beat.beatIndex % stripCount) + stripCount) % stripCount
        } else {
            column = Int(elapsed * speed * 2) % stripCount
        }

        for zone in Self.columnZones {
            frame[buttonNote: zone.notes[column]] = .solid
        }

        let functionNotes = XTouchSurfaceProtocol.ButtonZone.function.notes
        frame[buttonNote: functionNotes[column]] = .solid

        let transportNotes = XTouchSurfaceProtocol.ButtonZone.transport.notes
        frame[buttonNote: transportNotes[column % transportNotes.count]] = .solid

        let assignNotes = XTouchSurfaceProtocol.ButtonZone.assign.notes
        frame[buttonNote: assignNotes[column % assignNotes.count]] = .solid

        let cursorNotes = XTouchSurfaceProtocol.ButtonZone.cursor.notes
        frame[buttonNote: cursorNotes[column % cursorNotes.count]] = .solid

        let sweepPhase = (elapsed * speed * 3).truncatingRemainder(dividingBy: 1)
        let sweepPosition = Int(sweepPhase * 11)
        frame.rings = (0..<stripCount).map { strip in
            .init(mode: .wrap, position: strip == column ? 11 : sweepPosition)
        }

        let step = Int(elapsed * speed * 2)
        frame.scribbleColors = (0..<stripCount).map { strip in
            let raw = UInt8((((strip + step) % 7) + 7) % 7 + 1)
            return XTouchSurfaceProtocol.ScribbleColor(rawValue: raw) ?? .white
        }

        return frame
    }
}

/// Each encoder ring and scribble strip mirrors its corresponding fader's live position —
/// SELECT lights when a fader is nearly full up, MUTE when it's nearly all the way down.
public struct FaderMirrorSurfacePattern: SurfacePattern {
    public static let id = "faderMirror"
    public static let displayName = "Fader Mirror"

    public init() {}

    public func render(elapsed: TimeInterval, beat: BeatClockSnapshot, params: SurfacePatternParams, faders: [Double]) -> SurfaceFrame {
        var frame = SurfaceFrame.allOff
        let selectNotes = XTouchSurfaceProtocol.ButtonZone.select.notes
        let muteNotes = XTouchSurfaceProtocol.ButtonZone.mute.notes
        let globalViewNotes = XTouchSurfaceProtocol.ButtonZone.globalView.notes

        for strip in 0..<XTouchSurfaceProtocol.stripCount {
            let level = strip < faders.count ? min(max(faders[strip], 0), 1) : 0

            frame.rings[strip] = .init(mode: .wrap, position: Int((level * 11).rounded()))

            let colorRaw: UInt8 = level < 1.0 / 3.0 ? 2 : (level < 2.0 / 3.0 ? 3 : 1) // green, yellow, red
            frame.scribbleColors[strip] = XTouchSurfaceProtocol.ScribbleColor(rawValue: colorRaw) ?? .white

            frame[buttonNote: selectNotes[strip]] = level > 0.85 ? .solid : .off
            frame[buttonNote: muteNotes[strip]] = level < 0.15 ? .solid : .off
            frame[buttonNote: globalViewNotes[strip]] = level > 0.5 ? .solid : .off

            frame.scribbleTexts[strip] = ScribbleText(upper: "CH \(strip + 1)", lower: "")
        }

        return frame
    }
}

/// Darkens the whole surface.
public struct SurfaceOffPattern: SurfacePattern {
    public static let id = "off"
    public static let displayName = "Off"

    public init() {}

    public func render(elapsed: TimeInterval, beat: BeatClockSnapshot, params: SurfacePatternParams, faders: [Double]) -> SurfaceFrame {
        .allOff
    }
}

/// Convenience registry of all built-in surface patterns, for UI pickers.
public enum SurfacePatterns {
    public static let all: [any SurfacePattern] = [
        ZoneBeatFlashSurfacePattern(),
        ButtonChaseSurfacePattern(),
        FaderMirrorSurfacePattern(),
        SurfaceOffPattern()
    ]
}
