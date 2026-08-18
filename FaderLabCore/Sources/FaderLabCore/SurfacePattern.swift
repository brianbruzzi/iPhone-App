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
///
/// Design rule for every pattern below except `Off`: **a dark button is the exception, not
/// the default.** The X-Touch has ~105 individually-lightable LEDs; a pattern that only
/// ever lights one small zone at a time reads as "mostly broken" even when every button is
/// working correctly (this is exactly what prompted the Round 5 rewrite — see git history).
/// `.blink` is used as an "alive but not accented" baseline and `.solid` as the accent, so
/// the whole surface is doing something at all times rather than sitting mostly dark.
public protocol SurfacePattern {
    static var id: String { get }
    static var displayName: String { get }

    /// `faders` is `PatternEngine.lastKnownFaderValues`: the 9 most recent finite fader
    /// positions (0...1, channel strips 0-7 then master), for patterns that mirror what
    /// the faders are doing. Always finite; may be a different length than 9 if called
    /// directly (e.g. in tests) — implementations should tolerate that rather than crash.
    func render(elapsed: TimeInterval, beat: BeatClockSnapshot, params: SurfacePatternParams, faders: [Double]) -> SurfaceFrame
}

/// The whole surface blazes solid on the downbeat; as the beat advances past `intensity`,
/// zones progressively drop to a blink baseline (never fully dark) in a rotating order, so
/// which section "lets go" first changes every beat. The encoder rings pulse outward from
/// center, and the scribble strips step through a color per bar.
public struct ZoneBeatFlashSurfacePattern: SurfacePattern {
    public static let id = "beatFlash"
    public static let displayName = "Beat Flash"

    public init() {}

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

        let allZones = XTouchSurfaceProtocol.ButtonZone.allCases
        let zoneCount = allZones.count
        for zone in allZones {
            frame.fill(zone, with: .solid)
        }

        // `intensity` is how much of the beat stays fully lit before sections start
        // peeling off; higher intensity = the blaze holds longer. Peeled sections go to
        // `.blink`, never `.off` — the surface stays visibly alive through the whole beat.
        let cutoff = max(0.05, min(0.95, params.intensity))
        if beat.phase > cutoff {
            let dropProgress = min(1, (beat.phase - cutoff) / max(0.01, 1 - cutoff))
            let zonesToDrop = Int(dropProgress * Double(zoneCount))
            let rotation = ((beat.beatIndex % zoneCount) + zoneCount) % zoneCount
            for i in 0..<zonesToDrop {
                frame.fill(allZones[(i + rotation) % zoneCount], with: .blink)
            }
        }

        frame[buttonNote: Self.playButtonNote] = .blink

        let lit = beat.phase <= cutoff
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

/// Every zone blinks as a baseline, and a lit column sweeps across all of them in lockstep
/// (one accented note per zone, modulo-wrapped so it works regardless of a zone's actual
/// note count — the same safe wrap the 5-note `.transport` zone always needed). The
/// encoder rings and scribble strips chase along with it.
public struct ButtonChaseSurfacePattern: SurfacePattern {
    public static let id = "chase"
    public static let displayName = "Chase"

    public init() {}

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

        for zone in XTouchSurfaceProtocol.ButtonZone.allCases {
            let notes = zone.notes
            guard !notes.isEmpty else { continue }
            frame.fill(zone, with: .blink)
            frame[buttonNote: notes[column % notes.count]] = .solid
        }

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

/// Every zone on the surface reflects the live fader levels, like a bank of VU meters.
/// The 8-note channel-strip zones (REC, SOLO, V-Pot press, Function, Global View) form a
/// graduated "ladder" — a strip's fader lights progressively more rungs as it rises — while
/// SELECT/MUTE keep their original at-the-extremes meaning (bright at nearly-full/nearly-
/// empty). Zones that don't map 1:1 to a channel strip each track one fader's own level
/// (falling back to the bank average only if there are fewer faders than zones) rather than
/// a single shared average — with the Wave fader pattern, 9 phase-offset sines average to
/// an exact constant, which would otherwise leave this whole section frozen once it became
/// independently selectable as the X-Touch's "Other Buttons" show. Nothing not currently
/// accented goes fully dark — it drops to `.blink` — so the whole surface still reads as
/// "alive."
///
/// Shown as "Follow Faders" in both the channel-strip and Other Buttons pickers — it is
/// the default for the latter, where only its notes-40+ output survives the splice.
public struct FaderMirrorSurfacePattern: SurfacePattern {
    public static let id = "faderMirror"
    public static let displayName = "Follow Faders"

    public init() {}

    private static let ladderZones: [(zone: XTouchSurfaceProtocol.ButtonZone, threshold: Double)] = [
        (.rec, 0.2), (.solo, 0.35), (.vpotPress, 0.5), (.function, 0.65), (.globalView, 0.8)
    ]

    private static let meterZones: [XTouchSurfaceProtocol.ButtonZone] = [
        .assign, .bankNav, .miscToggles, .modifier, .automation, .utility, .cursor, .userSwitch, .transport, .indicator
    ]

    public func render(elapsed: TimeInterval, beat: BeatClockSnapshot, params: SurfacePatternParams, faders: [Double]) -> SurfaceFrame {
        var frame = SurfaceFrame.allOff
        let selectNotes = XTouchSurfaceProtocol.ButtonZone.select.notes
        let muteNotes = XTouchSurfaceProtocol.ButtonZone.mute.notes

        for strip in 0..<XTouchSurfaceProtocol.stripCount {
            let level = strip < faders.count ? min(max(faders[strip], 0), 1) : 0

            frame.rings[strip] = .init(mode: .wrap, position: Int((level * 11).rounded()))

            let colorRaw: UInt8 = level < 1.0 / 3.0 ? 2 : (level < 2.0 / 3.0 ? 3 : 1) // green, yellow, red
            frame.scribbleColors[strip] = XTouchSurfaceProtocol.ScribbleColor(rawValue: colorRaw) ?? .white

            frame[buttonNote: selectNotes[strip]] = level > 0.85 ? .solid : .blink
            frame[buttonNote: muteNotes[strip]] = level < 0.15 ? .solid : .blink

            for rung in Self.ladderZones {
                let notes = rung.zone.notes
                frame[buttonNote: notes[strip]] = level > rung.threshold ? .solid : .blink
            }

            frame.scribbleTexts[strip] = ScribbleText(upper: "CH \(strip + 1)", lower: "")
        }

        let averageLevel: Double = faders.isEmpty ? 0 : min(max(faders.reduce(0, +) / Double(faders.count), 0), 1)
        for (zoneIndex, zone) in Self.meterZones.enumerated() {
            // Each meter zone tracks its own fader rather than the bank average — see the
            // type doc comment for why the average alone isn't enough.
            let level = zoneIndex < faders.count
                ? min(max(faders[zoneIndex], 0), 1)
                : averageLevel
            let notes = zone.notes
            let litCount = Int((level * Double(notes.count)).rounded())
            for (index, note) in notes.enumerated() {
                frame[buttonNote: note] = index < litCount ? .solid : .blink
            }
        }

        return frame
    }
}

/// Maximum density: the entire surface lights solid, with a slow rolling blink band
/// traveling across it for a sense of motion even at full brightness. The go-to "everything
/// is on" look — also doubles as a visual proof that every LED actually responds, since
/// there's nowhere for a dead button to hide.
public struct FullSurfaceSurfacePattern: SurfacePattern {
    public static let id = "fullSurface"
    public static let displayName = "Full Surface"

    public init() {}

    public func render(elapsed: TimeInterval, beat: BeatClockSnapshot, params: SurfacePatternParams, faders: [Double]) -> SurfaceFrame {
        var frame = SurfaceFrame.allOff
        let allNotes = XTouchSurfaceProtocol.animatableButtonNotes
        for note in allNotes {
            frame[buttonNote: note] = .solid
        }

        let speed = max(params.speed, 0.01)
        let bandWidth = max(1, Int(Double(allNotes.count) * 0.12))
        let position = Int(elapsed * speed * 8) % allNotes.count
        for offset in 0..<bandWidth {
            let index = (position + offset) % allNotes.count
            frame[buttonNote: allNotes[index]] = .blink
        }

        frame.rings = Array(
            repeating: .init(mode: .spread, position: 11, centerLED: true),
            count: XTouchSurfaceProtocol.stripCount
        )
        frame.scribbleColors = Array(repeating: .white, count: XTouchSurfaceProtocol.stripCount)
        frame.scribbleTexts = Array(
            repeating: ScribbleText(upper: "FADER", lower: "LAB"),
            count: XTouchSurfaceProtocol.stripCount
        )

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
        FullSurfaceSurfacePattern(),
        ZoneBeatFlashSurfacePattern(),
        ButtonChaseSurfacePattern(),
        FaderMirrorSurfacePattern(),
        SurfaceOffPattern()
    ]
}
