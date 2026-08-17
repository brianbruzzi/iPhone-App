import Foundation
import Observation
import FaderLabCore

/// Composition root: owns `MIDIManager`, `AudioEngine`, and `PatternEngine`, wires them
/// together, and drives the ~30Hz animation tick that turns pattern output into MIDI
/// traffic. SwiftUI views bind directly to this object's published state.
@Observable
final class AppState {
    let midiManager = MIDIManager()
    let audioEngine = AudioEngine()
    let patternEngine = PatternEngine()

    var faderPatternID: String = WaveFaderPattern.id {
        didSet { applyFaderPattern() }
    }
    var padPatternID: String = PlasmaWavePattern.id {
        didSet { applyPadPattern() }
    }

    var faderSpeed = 1.0 { didSet { patternEngine.faderParams.speed = faderSpeed } }
    var faderAmplitude = 1.0 { didSet { patternEngine.faderParams.amplitude = faderAmplitude } }
    var faderBaseLevel = 0.5 { didSet { patternEngine.faderParams.baseLevel = faderBaseLevel } }

    var padSpeed = 1.0 { didSet { patternEngine.padParams.speed = padSpeed } }
    var padHueShift = 0.0 { didSet { patternEngine.padParams.hueShift = padHueShift } }
    var padBrightness = 1.0 { didSet { patternEngine.padParams.brightness = padBrightness } }

    var syncToBeat = true { didSet { patternEngine.syncToBeat = syncToBeat } }

    private(set) var midiStartError: String?
    private(set) var audioLoadError: String?

    private var startHostTime: TimeInterval = 0
    private var tickTimer: DispatchSourceTimer?
    private var lastSentPadGrid: PixelGrid?

    private static let tickInterval: TimeInterval = 1.0 / 30.0

    init() {
        wireCallbacks()
    }

    // MARK: - Lifecycle

    func start() {
        do {
            try midiManager.start()
            midiStartError = nil
        } catch {
            midiStartError = "MIDI setup failed: \(error)"
        }

        startHostTime = audioEngine.currentHostTimeSeconds()
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

        patternEngine.onFaderFrame = { [weak self] values in
            self?.sendFaderFrame(values)
        }
        patternEngine.onPadFrame = { [weak self] grid in
            self?.sendPadFrame(grid)
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
        let elapsed = now - startHostTime
        let beat = audioEngine.beatClock.snapshot(now: now)

        patternEngine.padParams.audioLevel = audioEngine.currentAudioLevel
        patternEngine.tick(elapsed: elapsed, beat: beat)

        audioEngine.refreshElapsedTime()
    }

    private func sendFaderFrame(_ values: [Double]) {
        for (index, value) in values.enumerated() where !value.isNaN {
            midiManager.sendXTouchFaderPosition(fader: index, value14: XTouchProtocol.value14(fromUnit: value))
        }
    }

    private func sendPadFrame(_ grid: PixelGrid) {
        guard grid != lastSentPadGrid else { return }
        lastSentPadGrid = grid
        midiManager.sendLaunchpadFrame(grid)
    }
}
