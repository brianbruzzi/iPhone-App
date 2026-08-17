import Foundation
import Observation
import FaderLabCore

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
    static let defaultFaderSpeed = 1.0
    static let defaultFaderAmplitude = 1.0
    static let defaultFaderBaseLevel = 0.5

    static let defaultPadPatternID = PlasmaWavePattern.id
    static let defaultPadSpeed = 1.0
    static let defaultPadHueShift = 0.0
    static let defaultPadBrightness = 1.0

    static let defaultSurfacePatternID = FullSurfaceSurfacePattern.id
    static let defaultSurfaceSpeed = 1.0
    static let defaultSurfaceIntensity = 1.0

    static let defaultXTouchSpeed = 1.0

    static let defaultSyncToBeat = true

    var faderPatternID: String = AppState.defaultFaderPatternID {
        didSet { applyFaderPattern() }
    }
    var padPatternID: String = AppState.defaultPadPatternID {
        didSet { applyPadPattern() }
    }

    var faderSpeed = AppState.defaultFaderSpeed { didSet { patternEngine.faderParams.speed = faderSpeed } }
    var faderAmplitude = AppState.defaultFaderAmplitude { didSet { patternEngine.faderParams.amplitude = faderAmplitude } }
    var faderBaseLevel = AppState.defaultFaderBaseLevel { didSet { patternEngine.faderParams.baseLevel = faderBaseLevel } }

    var padSpeed = AppState.defaultPadSpeed { didSet { patternEngine.padParams.speed = padSpeed } }
    var padHueShift = AppState.defaultPadHueShift { didSet { patternEngine.padParams.hueShift = padHueShift } }
    var padBrightness = AppState.defaultPadBrightness { didSet { patternEngine.padParams.brightness = padBrightness } }

    var surfacePatternID: String = AppState.defaultSurfacePatternID {
        didSet { applySurfacePattern() }
    }
    var surfaceSpeed = AppState.defaultSurfaceSpeed { didSet { patternEngine.surfaceParams.speed = surfaceSpeed } }
    var surfaceIntensity = AppState.defaultSurfaceIntensity { didSet { patternEngine.surfaceParams.intensity = surfaceIntensity } }

    /// A master control over the X-Touch as a whole: moving it sets both `faderSpeed` and
    /// `surfaceSpeed` to match. It's a fire-and-forget broadcast, not a live binding — the
    /// two individual sliders stay independently adjustable afterward, and this value goes
    /// stale (doesn't track them) until the master is moved again. Launchpad/`padSpeed` is
    /// untouched; it's a separate physical device.
    var xTouchSpeed = AppState.defaultXTouchSpeed {
        didSet {
            faderSpeed = xTouchSpeed
            surfaceSpeed = xTouchSpeed
        }
    }

    var syncToBeat = AppState.defaultSyncToBeat { didSet { patternEngine.syncToBeat = syncToBeat } }

    private(set) var midiStartError: String?
    private(set) var audioLoadError: String?

    /// Mirrors exactly what's being sent to the hardware, so the UI can preview both
    /// patterns on screen even without the X-Touch/Launchpad physically connected.
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
        faderSpeed = AppState.defaultFaderSpeed
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
        surfaceSpeed = AppState.defaultSurfaceSpeed
        surfaceIntensity = AppState.defaultSurfaceIntensity
    }

    func resetAll() {
        resetFaderSettings()
        resetPadSettings()
        resetSurfaceSettings()
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

        audioEngine.refreshElapsedTime()
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
