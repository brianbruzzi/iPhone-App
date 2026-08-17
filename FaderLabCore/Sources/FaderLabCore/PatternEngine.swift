import Foundation

/// Hardware-agnostic orchestrator: on every `tick`, asks the current `FaderPattern` and
/// `PadPattern` for a frame and hands each to a callback. Knows nothing about CoreMIDI —
/// the App target's `AppState` drives `tick(elapsed:beat:)` on a timer and forwards the
/// emitted frames to `MIDIManager`. This split is what keeps pattern logic testable
/// without any hardware or even a running app.
public final class PatternEngine {
    public var faderPattern: any FaderPattern
    public var padPattern: any PadPattern
    public var faderParams = FaderPatternParams()
    public var padParams = PadPatternParams()

    /// When false, patterns receive `BeatClockSnapshot.idle` instead of the live beat,
    /// so purely time-driven patterns (Wave, Plasma, Rainbow) keep animating for testing
    /// without audio, while beat-linked mechanics go neutral/static.
    public var syncToBeat: Bool = true

    /// Faders the user currently has a finger on (from `MIDIManager`'s touch-sense
    /// callbacks). Automation is suspended for these indices each tick so the motor
    /// doesn't fight the user's hand.
    public var touchedFaders: Set<Int> = []

    /// Emits `XTouchProtocol.faderCount` target positions each tick (0...1, or `.nan` to
    /// mean "send nothing for this fader" — see `FaderPattern`).
    public var onFaderFrame: (([Double]) -> Void)?
    /// Emits a full 8x8 pixel-art frame each tick.
    public var onPadFrame: ((PixelGrid) -> Void)?

    public init(
        faderPattern: any FaderPattern = WaveFaderPattern(),
        padPattern: any PadPattern = PlasmaWavePattern()
    ) {
        self.faderPattern = faderPattern
        self.padPattern = padPattern
    }

    /// Advances all patterns by one animation frame. `elapsed` is seconds since the engine
    /// (or the audio transport) started; `beat` is the current live beat clock snapshot.
    public func tick(elapsed: TimeInterval, beat: BeatClockSnapshot) {
        let effectiveBeat = syncToBeat ? beat : .idle

        var faders = faderPattern.faderValues(elapsed: elapsed, beat: effectiveBeat, params: faderParams)
        for index in touchedFaders where faders.indices.contains(index) {
            faders[index] = .nan
        }
        onFaderFrame?(faders)

        let grid = padPattern.render(elapsed: elapsed, beat: effectiveBeat, params: padParams)
        onPadFrame?(grid)
    }
}
