import Foundation
import Observation
import FaderLabCore

/// What drives the X-Touch's 8 hardware VU meters. They're independent of the button/ring
/// light show — the meters are their own physical LED strips with their own auto-decaying
/// protocol — so they get their own source selection rather than following a pattern.
enum VUMeterSource: String, CaseIterable, Identifiable {
    case off
    case faders
    case audioLevel

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .faders: return "Follow Faders"
        case .audioLevel: return "Audio Level"
        }
    }
}

/// Composition root: owns `MIDIManager`, `AudioEngine`, and `PatternEngine`, wires them
/// together, and drives the 60Hz animation tick (faders every tick, pads/surface every
/// other tick) that turns pattern output into MIDI traffic. SwiftUI views bind directly to
/// this object's published state.
@Observable
final class AppState {
    let midiManager = MIDIManager()
    let audioEngine = AudioEngine()
    let patternEngine = PatternEngine()

    // MARK: - Defaults (also used by the Reset buttons in the UI)

    static let defaultFaderPatternID = WaveFaderPattern.id
    static let defaultFaderAmplitude = 1.0
    static let defaultFaderBaseLevel = 0.5

    static let defaultPadPatternID = PlasmaWavePattern.id
    static let defaultPadSpeed = 1.0
    static let defaultPadHueShift = 0.0
    static let defaultPadBrightness = 1.0

    static let defaultSurfacePatternID = FullSurfaceSurfacePattern.id
    static let defaultSurfaceIntensity = 1.0
    static let defaultSurfaceReversed = false

    static let defaultRightSectionPatternID = FaderMirrorSurfacePattern.id
    static let defaultRightSectionIntensity = 1.0

    static let defaultXTouchSpeed = 1.0

    static let defaultVUMeterSource = VUMeterSource.faders
    static let defaultDisplayText = "FADER LAB"

    static let defaultSyncToBeat = true

    var faderPatternID: String = AppState.defaultFaderPatternID {
        didSet { applyFaderPattern() }
    }
    var padPatternID: String = AppState.defaultPadPatternID {
        didSet { applyPadPattern() }
    }

    var faderAmplitude = AppState.defaultFaderAmplitude { didSet { patternEngine.faderParams.amplitude = faderAmplitude } }
    var faderBaseLevel = AppState.defaultFaderBaseLevel { didSet { patternEngine.faderParams.baseLevel = faderBaseLevel } }

    var padSpeed = AppState.defaultPadSpeed { didSet { patternEngine.padParams.speed = padSpeed } }
    var padHueShift = AppState.defaultPadHueShift { didSet { patternEngine.padParams.hueShift = padHueShift } }
    var padBrightness = AppState.defaultPadBrightness { didSet { patternEngine.padParams.brightness = padBrightness } }

    var surfacePatternID: String = AppState.defaultSurfacePatternID {
        didSet { applySurfacePattern() }
    }
    var surfaceIntensity = AppState.defaultSurfaceIntensity { didSet { patternEngine.surfaceParams.intensity = surfaceIntensity } }
    /// Flips which end of the SELECT/MUTE/SOLO/REC meter fills first. Only affects
    /// "Follow Faders" — other channel-strip patterns have no inherent direction.
    var surfaceReversed = AppState.defaultSurfaceReversed { didSet { patternEngine.surfaceParams.reversed = surfaceReversed } }

    /// The X-Touch's right-hand button cluster (notes 40+), selectable independently of the
    /// channel-strip light show — same pattern list, its own selection. Defaults to
    /// "Follow Faders" so it reads as an extension of the fader show.
    var rightSectionPatternID: String = AppState.defaultRightSectionPatternID {
        didSet { applyRightSectionPattern() }
    }
    var rightSectionIntensity = AppState.defaultRightSectionIntensity {
        didSet { patternEngine.rightSectionParams.intensity = rightSectionIntensity }
    }

    /// The single speed control for everything on the X-Touch: fader motion, the
    /// channel-strip light show, and the right-hand button cluster. There are no per-section
    /// speed sliders — this writes straight through to all three param structs rather than
    /// broadcasting into intermediate properties that could drift independently. Launchpad/
    /// `padSpeed` is untouched; it's a separate physical device with its own card.
    var xTouchSpeed = AppState.defaultXTouchSpeed {
        didSet {
            patternEngine.faderParams.speed = xTouchSpeed
            patternEngine.surfaceParams.speed = xTouchSpeed
            patternEngine.rightSectionParams.speed = xTouchSpeed
        }
    }

    /// Drives the 8 hardware VU meters. Switching away from `.off` re-enables the meters on
    /// the surface; switching to `.off` blanks them.
    var vuMeterSource = AppState.defaultVUMeterSource {
        didSet {
            guard vuMeterSource != oldValue else { return }
            midiManager.sendXTouchVUEnabled(vuMeterSource != .off)
        }
    }

    /// Text shown on the X-Touch's 12-digit 7-segment display. Being 7-segment, some
    /// letters (M, W, K, V, X) only render as rough approximations.
    var displayText = AppState.defaultDisplayText {
        didSet { midiManager.sendXTouchDisplayText(displayText) }
    }

    var syncToBeat = AppState.defaultSyncToBeat { didSet { patternEngine.syncToBeat = syncToBeat } }

    private(set) var midiStartError: String?
    private(set) var audioLoadError: String?

    /// Mirrors exactly what's being sent to the hardware, so the UI can preview every
    /// pattern on screen even without the X-Touch/Launchpad physically connected.
    private(set) var latestFaderValues = [Double](repeating: 0.5, count: XTouchProtocol.faderCount)
    private(set) var latestPadGrid = PixelGrid.allBlack
    private(set) var latestSurfaceFrame = SurfaceFrame.allOff

    /// Whether the show is currently paused. Paused freezes the hardware exactly where it
    /// is (patterns simply stop being ticked) while the 60Hz timer itself keeps running, so
    /// audio time, hand-moved-fader mirroring, and diagnostics all stay live.
    private(set) var isPatternPaused = false

    private var transportClock = TransportClock(startedAt: 0)
    private var tickTimer: DispatchSourceTimer?
    private var tickCount = 0

    /// 60Hz overall so faders (ticked every call) update smoothly; pads and the X-Touch
    /// surface only need every other tick (~30Hz) — see `tick()`.
    private static let tickInterval: TimeInterval = 1.0 / 60.0

    init() {
        wireCallbacks()
    }

    // MARK: - Lifecycle

    func start() {
        do {
            try midiManager.start()
            midiStartError = nil
        } catch let error as MIDIManagerError {
            midiStartError = error.description
        } catch {
            midiStartError = "MIDI setup failed: \(error)"
        }

        // Both live outside the diffed surface frame, so nothing else would push them to
        // the hardware on connect — the display would sit blank and the meters inert until
        // the user happened to change one.
        midiManager.sendXTouchVUEnabled(vuMeterSource != .off)
        midiManager.sendXTouchDisplayText(displayText)

        transportClock = TransportClock(startedAt: audioEngine.currentHostTimeSeconds())
        isPatternPaused = false
        startTickTimer()
    }

    func stop() {
        stopTickTimer()
        midiManager.stop()
    }

    // MARK: - User actions

    func loadAudioFile(url: URL) {
        do {
            try audioEngine.load(url: url)
            audioLoadError = nil
        } catch {
            audioLoadError = "Couldn't load \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Pauses or resumes the whole show. Resuming never causes a time jump: `TransportClock`
    /// accumulates run time rather than anchoring to a start instant.
    func togglePatternPause() {
        let now = audioEngine.currentHostTimeSeconds()
        if isPatternPaused {
            transportClock.resume(at: now)
        } else {
            transportClock.pause(at: now)
        }
        isPatternPaused.toggle()
    }

    // MARK: - Reset to defaults

    func resetFaderSettings() {
        faderPatternID = AppState.defaultFaderPatternID
        faderAmplitude = AppState.defaultFaderAmplitude
        faderBaseLevel = AppState.defaultFaderBaseLevel
    }

    func resetPadSettings() {
        padPatternID = AppState.defaultPadPatternID
        padSpeed = AppState.defaultPadSpeed
        padHueShift = AppState.defaultPadHueShift
        padBrightness = AppState.defaultPadBrightness
    }

    func resetSurfaceSettings() {
        surfacePatternID = AppState.defaultSurfacePatternID
        surfaceIntensity = AppState.defaultSurfaceIntensity
        surfaceReversed = AppState.defaultSurfaceReversed
    }

    func resetRightSectionSettings() {
        rightSectionPatternID = AppState.defaultRightSectionPatternID
        rightSectionIntensity = AppState.defaultRightSectionIntensity
    }

    /// The X-Touch card's Reset button — all three of its sections at once. Deliberately
    /// does *not* touch `xTouchSpeed`: that slider lives in the transport bar, carries its
    /// own inline reset, and is covered by Reset Everything.
    func resetXTouchSettings() {
        resetFaderSettings()
        resetSurfaceSettings()
        resetRightSectionSettings()
        vuMeterSource = AppState.defaultVUMeterSource
        displayText = AppState.defaultDisplayText
    }

    func resetAll() {
        resetXTouchSettings()
        resetPadSettings()
        // The only path that resets all three X-Touch speeds at once — `didSet` fires on
        // every assignment in Swift, including a no-op one, so this always re-syncs the
        // params even if xTouchSpeed was already at its default.
        xTouchSpeed = AppState.defaultXTouchSpeed
        syncToBeat = AppState.defaultSyncToBeat
    }

    // MARK: - Wiring

    private func wireCallbacks() {
        midiManager.onXTouchFaderTouch = { [weak self] index, touched in
            guard let self else { return }
            if touched {
                self.patternEngine.touchedFaders.insert(index)
            } else {
                self.patternEngine.touchedFaders.remove(index)
            }
        }

        // Mirror hand-moved faders into the on-screen preview. Doubles as a live proof that
        // input from the surface is reaching the app at all.
        midiManager.onXTouchFaderPositionReport = { [weak self] index, unitValue in
            guard let self, self.latestFaderValues.indices.contains(index) else { return }
            self.latestFaderValues[index] = unitValue
        }

        patternEngine.onFaderFrame = { [weak self] values in
            guard let self else { return }
            // NaN means "no automation this tick" (touched/manual-off) — keep showing the
            // last known position for that fader rather than propagating NaN into the UI.
            var display = self.latestFaderValues
            for (index, value) in values.enumerated() where !value.isNaN {
                display[index] = value
            }
            self.latestFaderValues = display
            self.sendFaderFrame(values)
        }
        patternEngine.onPadFrame = { [weak self] grid in
            self?.latestPadGrid = grid
            self?.sendPadFrame(grid)
        }
        patternEngine.onSurfaceFrame = { [weak self] frame in
            self?.latestSurfaceFrame = frame
            self?.sendSurfaceFrame(frame)
        }
    }

    private func applyFaderPattern() {
        guard let pattern = FaderPatterns.all.first(where: { type(of: $0).id == faderPatternID }) else { return }
        patternEngine.faderPattern = pattern
    }

    private func applyPadPattern() {
        guard let pattern = PadPatterns.all.first(where: { type(of: $0).id == padPatternID }) else { return }
        patternEngine.padPattern = pattern
    }

    private func applySurfacePattern() {
        guard let pattern = SurfacePatterns.all.first(where: { type(of: $0).id == surfacePatternID }) else { return }
        patternEngine.surfacePattern = pattern
    }

    private func applyRightSectionPattern() {
        guard let pattern = SurfacePatterns.all.first(where: { type(of: $0).id == rightSectionPatternID }) else { return }
        patternEngine.rightSectionPattern = pattern
    }

    // MARK: - Tick loop

    private func startTickTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: AppState.tickInterval)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        tickTimer = timer
    }

    private func stopTickTimer() {
        tickTimer?.cancel()
        tickTimer = nil
    }

    private func tick() {
        let now = audioEngine.currentHostTimeSeconds()
        let elapsed = transportClock.elapsed(at: now)
        let beat = audioEngine.beatClock.snapshot(now: now)

        // Faders every tick (60Hz) for smooth motor motion; pads + surface every other
        // tick (~30Hz) — Launchpad SysEx and the X-Touch surface don't need faster than
        // that, and running them at 60Hz would double MIDI traffic for no visible gain.
        var components: TickComponents = .faders
        if tickCount.isMultiple(of: 2) {
            components.formUnion([.pads, .surface])
        }
        tickCount += 1

        patternEngine.padParams.audioLevel = audioEngine.currentAudioLevel
        if !isPatternPaused {
            patternEngine.tick(elapsed: elapsed, beat: beat, components: components)
        }

        // VU meters get their own cadence: they decay in hardware (~300ms per division), so
        // they need continuous re-sending rather than the diff-on-change treatment the rest
        // of the surface gets. Every 4th tick (15Hz) is far quicker than the decay while
        // costing a fraction of the traffic of doing it every frame.
        if tickCount.isMultiple(of: 4) {
            sendVUFrameIfNeeded()
        }

        audioEngine.refreshElapsedTime()
    }

    private func sendVUFrameIfNeeded() {
        // Paused freezes the hardware where it is for the button/fader show, but VU meters
        // physically can't hold — they'd sag to nothing regardless — so keep feeding them
        // the frozen levels rather than letting them decay to a misleading zero.
        switch vuMeterSource {
        case .off:
            return
        case .faders:
            midiManager.sendXTouchVULevels(latestFaderValues)
        case .audioLevel:
            let level = audioEngine.currentAudioLevel
            midiManager.sendXTouchVULevels(
                [Double](repeating: level, count: XTouchSurfaceProtocol.stripCount)
            )
        }
    }

    private func sendFaderFrame(_ values: [Double]) {
        midiManager.sendXTouchFaderFrame(values)
    }

    private func sendPadFrame(_ grid: PixelGrid) {
        // Deduping lives in MIDIManager now: it's the one place that sees every path that
        // touches the Launchpad (pattern frames, and the diagnostics panel's direct
        // clear/re-enter-Programmer-mode commands), so it's the only place that can
        // actually know whether a frame matches what's on the hardware.
        midiManager.sendLaunchpadFrame(grid)
    }

    private func sendSurfaceFrame(_ frame: SurfaceFrame) {
        midiManager.sendXTouchSurfaceFrame(frame)
    }
}
