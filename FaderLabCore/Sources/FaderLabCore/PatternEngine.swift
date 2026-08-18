import Foundation

/// Which frame kinds a `PatternEngine.tick(...)` call should compute and emit. Lets a
/// caller run faders at a higher rate than pads/surface (the fader-buzz fix needs faders
/// updated every tick, while Launchpad SysEx and the X-Touch surface stay smooth at a
/// lower rate) without needing two separate engines or duplicated beat/elapsed state.
public struct TickComponents: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let faders = TickComponents(rawValue: 1 << 0)
    public static let pads = TickComponents(rawValue: 1 << 1)
    public static let surface = TickComponents(rawValue: 1 << 2)

    public static let all: TickComponents = [.faders, .pads, .surface]
}

/// Hardware-agnostic orchestrator: on every `tick`, asks the current `FaderPattern`,
/// `PadPattern`, and `SurfacePattern` for a frame and hands each to a callback. Knows
/// nothing about CoreMIDI — the App target's `AppState` drives `tick(elapsed:beat:)` on a
/// timer and forwards the emitted frames to `MIDIManager`. This split is what keeps
/// pattern logic testable without any hardware or even a running app.
public final class PatternEngine {
    public var faderPattern: any FaderPattern
    public var padPattern: any PadPattern
    public var surfacePattern: any SurfacePattern
    public var faderParams = FaderPatternParams()
    public var padParams = PadPatternParams()
    public var surfaceParams = SurfacePatternParams()

    /// Drives the X-Touch's right-hand control cluster (notes 40+, see
    /// `XTouchSurfaceProtocol.rightSectionZones`) independently of the channel-strip show.
    /// Rendered as its own full frame each tick and then spliced over `surfacePattern`'s
    /// output — only its *button* states for those notes are kept. The encoder rings and
    /// scribble strips are physically part of the channel strips, so they always come from
    /// `surfacePattern` no matter what is selected here.
    ///
    /// Defaults to `FaderMirrorSurfacePattern` ("Follow Faders"), which makes the cluster
    /// read as an extension of the fader show out of the box.
    public var rightSectionPattern: any SurfacePattern = FaderMirrorSurfacePattern()
    public var rightSectionParams = SurfacePatternParams()

    /// When false, patterns receive `BeatClockSnapshot.idle` instead of the live beat,
    /// so purely time-driven patterns (Wave, Plasma, Rainbow) keep animating for testing
    /// without audio, while beat-linked mechanics go neutral/static.
    public var syncToBeat: Bool = true

    /// Faders the user currently has a finger on (from `MIDIManager`'s touch-sense
    /// callbacks). Automation is suspended for these indices each tick so the motor
    /// doesn't fight the user's hand.
    public var touchedFaders: Set<Int> = []

    /// The most recent finite fader position (0...1) seen per index, for surface patterns
    /// that mirror what the faders are doing (see `SurfacePattern.render`'s `faders`
    /// parameter). Touched faders (which emit `.nan`) simply keep their last known value
    /// here rather than going stale to NaN. Starts at 0.5 (neutral) before the first tick.
    public private(set) var lastKnownFaderValues: [Double]

    /// Emits `XTouchProtocol.faderCount` target positions each tick (0...1, or `.nan` to
    /// mean "send nothing for this fader" — see `FaderPattern`).
    public var onFaderFrame: (([Double]) -> Void)?
    /// Emits a full 8x8 pixel-art frame each tick.
    public var onPadFrame: ((PixelGrid) -> Void)?
    /// Emits a full X-Touch surface lighting frame each tick.
    public var onSurfaceFrame: ((SurfaceFrame) -> Void)?

    public init(
        faderPattern: any FaderPattern = WaveFaderPattern(),
        padPattern: any PadPattern = PlasmaWavePattern(),
        surfacePattern: any SurfacePattern = FullSurfaceSurfacePattern()
    ) {
        self.faderPattern = faderPattern
        self.padPattern = padPattern
        self.surfacePattern = surfacePattern
        self.lastKnownFaderValues = Array(repeating: 0.5, count: XTouchProtocol.faderCount)
    }

    /// Advances the requested `components` by one animation frame. `elapsed` is seconds
    /// since the engine (or the audio transport) started; `beat` is the current live beat
    /// clock snapshot. Defaults to `.all` so existing single-rate callers are unaffected.
    public func tick(elapsed: TimeInterval, beat: BeatClockSnapshot, components: TickComponents = .all) {
        let effectiveBeat = syncToBeat ? beat : .idle

        if components.contains(.faders) {
            var faders = faderPattern.faderValues(elapsed: elapsed, beat: effectiveBeat, params: faderParams)
            for index in touchedFaders where faders.indices.contains(index) {
                faders[index] = .nan
            }
            updateLastKnownFaderValues(from: faders)
            onFaderFrame?(faders)
        }

        if components.contains(.pads) {
            let grid = padPattern.render(elapsed: elapsed, beat: effectiveBeat, params: padParams)
            onPadFrame?(grid)
        }

        if components.contains(.surface) {
            var frame = surfacePattern.render(
                elapsed: elapsed, beat: effectiveBeat, params: surfaceParams, faders: lastKnownFaderValues
            )
            // The right-hand cluster is rendered separately and spliced over the top, so
            // the two sections are genuinely independent. `surfacePattern`'s own output for
            // notes 40+ is discarded here — a few wasted array writes in a pure function,
            // which is the price of every existing SurfacePattern continuing to render a
            // full frame with zero changes (see the Round 5 density tests).
            let rightFrame = rightSectionPattern.render(
                elapsed: elapsed, beat: effectiveBeat, params: rightSectionParams, faders: lastKnownFaderValues
            )
            for index in XTouchSurfaceProtocol.rightSectionButtonIndices {
                frame.buttons[index] = rightFrame.buttons[index]
            }
            onSurfaceFrame?(frame)
        }
    }

    private func updateLastKnownFaderValues(from faders: [Double]) {
        if faders.count != lastKnownFaderValues.count {
            lastKnownFaderValues = Array(repeating: 0.5, count: faders.count)
        }
        for (index, value) in faders.enumerated() where value.isFinite {
            lastKnownFaderValues[index] = value
        }
    }
}
