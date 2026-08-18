import AVFoundation
import Darwin
import Observation
import FaderLabCore

/// Plays a user-selected audio file and analyzes it locally for beat detection: a tap on
/// the player node feeds raw sample buffers into `SpectralFluxOnsetDetector`, whose
/// onsets update the shared `BeatClock` that both the fader and Launchpad pattern engines
/// read from. This is the only file in the app that imports AVFoundation.
@Observable
final class AudioEngine {
    private(set) var isPlaying = false
    private(set) var trackURL: URL?
    private(set) var currentBPM: Double = 120
    /// Smoothed 0...1 audio level from the most recent tap buffer, consumed by
    /// audio-level-driven pad patterns (e.g. VU columns).
    private(set) var currentAudioLevel: Double = 0
    /// Playback position in seconds, refreshed once per animation tick by `AppState`
    /// (rather than running its own timer) — see `refreshElapsedTime()`.
    private(set) var elapsedSeconds: TimeInterval = 0
    /// Length of the loaded track, or 0 if none. Used to wrap the position readout when
    /// looping — see `refreshElapsedTime()`.
    private(set) var trackDuration: TimeInterval = 0

    /// When true, reaching the end of the track immediately restarts it instead of
    /// stopping. Safe to toggle mid-playback — it's read when the current schedule
    /// finishes, not captured when playback starts.
    var isLooping = false

    /// Shared beat clock — the single source of truth both pattern engines read from.
    let beatClock = BeatClock()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var onsetDetector: SpectralFluxOnsetDetector?
    private var audioFile: AVAudioFile?

    private let tapBufferSize: AVAudioFrameCount = 1024

    /// Bumped every time a file is (re)scheduled, so a stale completion handler from a
    /// schedule that `stop()`/`restartFromBeginning()` has since superseded can't clobber
    /// `isPlaying` after a fresh one has already started. AVAudioPlayerNode invokes a
    /// segment's completion handler when it's displaced, not just when it finishes
    /// naturally, so without this guard rapid stop/restart taps could flicker Play back to
    /// Pause a moment after the user pressed it.
    private var scheduleGeneration = 0

    init() {
        engine.attach(player)
    }

    // MARK: - Loading / transport

    func load(url: URL) throws {
        stopInternal()

        let file = try AVAudioFile(forReading: url)
        audioFile = file
        trackURL = url
        trackDuration = file.processingFormat.sampleRate > 0
            ? Double(file.length) / file.processingFormat.sampleRate
            : 0

        let format = file.processingFormat
        engine.connect(player, to: engine.mainMixerNode, format: format)
        onsetDetector = SpectralFluxOnsetDetector(sampleRate: format.sampleRate, fftSize: Int(tapBufferSize))
        installTap(format: format)

        if !engine.isRunning {
            try engine.start()
        }

        scheduleFromStart()
    }

    func play() {
        guard !isPlaying, audioFile != nil else { return }
        player.play()
        isPlaying = true
    }

    func pause() {
        guard isPlaying else { return }
        player.pause()
        isPlaying = false
    }

    /// Stops playback and resets to the beginning — same as loading the track fresh, so
    /// pressing Play afterward starts over from 0.
    func stop() {
        guard audioFile != nil else { return }
        player.stop()
        isPlaying = false
        elapsedSeconds = 0
        scheduleFromStart()
    }

    /// Seeks back to the beginning without changing whether playback is running: still
    /// playing afterward if it was playing, still paused if it was paused.
    func restartFromBeginning() {
        guard audioFile != nil else { return }
        let wasPlaying = isPlaying
        player.stop()
        elapsedSeconds = 0
        scheduleFromStart()
        if wasPlaying {
            player.play()
            isPlaying = true
        }
    }

    /// (Re)schedules the whole loaded file from its beginning — `AVAudioPlayerNode.
    /// scheduleFile` always plays a file from frame 0, so this is also how `stop()` and
    /// `restartFromBeginning()` seek back to the start.
    private func scheduleFromStart() {
        guard let file = audioFile else { return }
        scheduleGeneration += 1
        let generation = scheduleGeneration
        player.scheduleFile(file, at: nil) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.scheduleGeneration == generation else { return }
                // Looping re-arms the file rather than stopping. `isPlaying` is left alone
                // so the transport never flickers to Paused between laps; the node keeps
                // running, it just gets another segment queued behind the one that ended.
                if self.isLooping, self.isPlaying {
                    self.scheduleFromStart()
                    self.player.play()
                } else {
                    self.isPlaying = false
                }
            }
        }
    }

    /// Sets tempo directly (e.g. from a UI field) for use before any track is loaded, or
    /// to override a live estimate. Re-anchors beat phase to now.
    func setManualBPM(_ bpm: Double) {
        beatClock.setManualBPM(bpm, now: currentHostTimeSeconds())
        currentBPM = beatClock.bpm
    }

    /// Called once per animation tick by `AppState` to refresh the playback-position
    /// readout, rather than running a second timer inside this class.
    func refreshElapsedTime() {
        guard let nodeTime = player.lastRenderTime, let playerTime = player.playerTime(forNodeTime: nodeTime) else {
            return
        }
        let raw = Double(playerTime.sampleTime) / playerTime.sampleRate
        // A loop re-schedules without stopping the node, so `sampleTime` keeps counting up
        // across laps rather than resetting — wrap it so the readout shows the position
        // within the track instead of total time played.
        elapsedSeconds = trackDuration > 0 ? raw.truncatingRemainder(dividingBy: trackDuration) : raw
    }

    /// "Now" in the same host-time base the audio tap stamps onsets with, for taking a
    /// `BeatClock` snapshot outside the tap callback (e.g. from the animation tick timer).
    func currentHostTimeSeconds() -> TimeInterval {
        AVAudioTime.seconds(forHostTime: mach_absolute_time())
    }

    // MARK: - Tap / analysis

    private func installTap(format: AVAudioFormat) {
        player.removeTap(onBus: 0)
        player.installTap(onBus: 0, bufferSize: tapBufferSize, format: format) { [weak self] buffer, when in
            self?.processTap(buffer, at: when)
        }
    }

    private func processTap(_ buffer: AVAudioPCMBuffer, at when: AVAudioTime) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let channelCount = Int(buffer.format.channelCount)
        var monoSamples = [Float](repeating: 0, count: frameCount)
        for channel in 0..<channelCount {
            let data = channelData[channel]
            for i in 0..<frameCount {
                monoSamples[i] += data[i]
            }
        }
        if channelCount > 1 {
            let scale = Float(1.0 / Double(channelCount))
            for i in 0..<frameCount { monoSamples[i] *= scale }
        }

        var sumSquares: Float = 0
        for sample in monoSamples { sumSquares += sample * sample }
        let rms = (sumSquares / Float(frameCount)).squareRoot()
        // Small fixed gain so typical music levels read as a usable 0...1 range rather
        // than clustering near zero (RMS of normalized audio is usually well under 1.0).
        let level = Double(min(max(rms * 4, 0), 1))

        let hostSeconds = AVAudioTime.seconds(forHostTime: when.hostTime)
        guard let detector = onsetDetector else {
            DispatchQueue.main.async { [weak self] in self?.currentAudioLevel = level }
            return
        }
        let onsets = detector.process(samples: monoSamples, timeSeconds: hostSeconds)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.currentAudioLevel = level
            for onset in onsets {
                self.beatClock.ingest(onsetAt: onset.timeSeconds)
            }
            if !onsets.isEmpty {
                self.currentBPM = self.beatClock.bpm
            }
        }
    }

    private func stopInternal() {
        if isPlaying {
            player.stop()
        }
        player.removeTap(onBus: 0)
        isPlaying = false
        onsetDetector = nil
    }
}
