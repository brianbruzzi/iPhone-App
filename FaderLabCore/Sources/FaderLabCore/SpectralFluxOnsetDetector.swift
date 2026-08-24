import Foundation
import Accelerate

public struct OnsetEvent: Equatable {
    public let timeSeconds: TimeInterval
    public let strength: Float

    public init(timeSeconds: TimeInterval, strength: Float) {
        self.timeSeconds = timeSeconds
        self.strength = strength
    }
}

/// Onset (transient) detector using spectral flux: windowed FFT magnitude spectra are
/// compared frame-to-frame, and the positive (rising-energy) part of the difference is
/// summed into a single onset-detection-function value per frame. An onset is reported
/// the instant that value rises above an adaptively-tracked threshold (a rising-edge
/// crossing, not "any frame above threshold"), subject to a debounce interval.
///
/// This reliably catches percussive transients; it does not by itself solve true
/// beat-induction (distinguishing "the beat" from "any transient") — see `BeatClock` and
/// the plan doc for how the two combine, and their honestly-scoped limitations.
///
/// Pure Swift + Accelerate/vDSP — no AVFoundation dependency, so it can be fed synthetic
/// `[Float]` buffers in tests without any audio session or real playback.
public final class SpectralFluxOnsetDetector {
    public let sampleRate: Double
    public let fftSize: Int

    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private let window: [Float]
    private var previousMagnitudes: [Float]

    private var fluxHistory: [Float] = []
    private let fluxHistoryCapacity: Int
    private var wasAboveThreshold = false
    private var lastAcceptedOnsetTime: TimeInterval?
    private let minInterOnsetInterval: TimeInterval
    private let thresholdMultiplier: Float

    /// - Parameters:
    ///   - sampleRate: sample rate of the audio being fed in, in Hz.
    ///   - fftSize: analysis window size in samples; must be a power of two. 1024 at
    ///     44.1kHz is ~23ms per frame, a reasonable latency/resolution tradeoff.
    ///   - historySeconds: how much recent flux history to keep for adaptive thresholding.
    ///   - minInterOnsetInterval: minimum seconds between accepted onsets (debounce), caps
    ///     the maximum detectable onset rate and rejects double-triggers on a single hit.
    ///   - thresholdMultiplier: how far above the recent mean flux a frame must rise to
    ///     count as an onset.
    public init(
        sampleRate: Double,
        fftSize: Int = 1024,
        historySeconds: Double = 1.5,
        minInterOnsetInterval: TimeInterval = 0.12,
        thresholdMultiplier: Float = 1.4
    ) {
        precondition(fftSize > 0 && (fftSize & (fftSize - 1)) == 0, "fftSize must be a power of two")
        self.sampleRate = sampleRate
        self.fftSize = fftSize
        let log2nValue = vDSP_Length(log2(Double(fftSize)))
        self.log2n = log2nValue
        self.fftSetup = vDSP_create_fftsetup(log2nValue, FFTRadix(kFFTRadix2))!
        self.window = SpectralFluxOnsetDetector.hannWindow(size: fftSize)
        self.previousMagnitudes = [Float](repeating: 0, count: fftSize / 2)
        let framesPerSecond = sampleRate / Double(fftSize)
        self.fluxHistoryCapacity = max(4, Int(historySeconds * framesPerSecond))
        self.minInterOnsetInterval = minInterOnsetInterval
        self.thresholdMultiplier = thresholdMultiplier
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Processes one buffer of mono samples. `timeSeconds` is the host/track time at the
    /// START of this buffer. Returns any onset detected within it (0 or 1 per call for
    /// reasonably small buffers — the debounce window prevents more than one). If
    /// `samples.count` != `fftSize`, the buffer is zero-padded/truncated to fftSize.
    public func process(samples: [Float], timeSeconds: TimeInterval) -> [OnsetEvent] {
        var frame = samples
        if frame.count < fftSize {
            frame.append(contentsOf: [Float](repeating: 0, count: fftSize - frame.count))
        } else if frame.count > fftSize {
            frame = Array(frame[0..<fftSize])
        }

        let magnitudes = magnitudeSpectrum(of: frame)

        var flux: Float = 0
        for i in 0..<magnitudes.count {
            let diff = magnitudes[i] - previousMagnitudes[i]
            if diff > 0 { flux += diff }
        }
        previousMagnitudes = magnitudes

        // Threshold is computed from history BEFORE this frame is folded in, so a single
        // huge spike can't inflate the very threshold it needs to clear.
        let threshold = adaptiveThreshold()
        let isAboveThreshold = flux > threshold

        fluxHistory.append(flux)
        if fluxHistory.count > fluxHistoryCapacity {
            fluxHistory.removeFirst(fluxHistory.count - fluxHistoryCapacity)
        }

        defer { wasAboveThreshold = isAboveThreshold }

        // Only fire on the rising edge (the instant flux climbs above threshold), not on
        // every subsequent frame that happens to still be above it.
        guard isAboveThreshold, !wasAboveThreshold else { return [] }

        if let last = lastAcceptedOnsetTime, timeSeconds - last < minInterOnsetInterval {
            return []
        }

        lastAcceptedOnsetTime = timeSeconds
        return [OnsetEvent(timeSeconds: timeSeconds, strength: flux)]
    }

    // MARK: - Spectrum

    private func magnitudeSpectrum(of frame: [Float]) -> [Float] {
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        var realp = [Float](repeating: 0, count: fftSize / 2)
        var imagp = [Float](repeating: 0, count: fftSize / 2)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)

        realp.withUnsafeMutableBufferPointer { realPtr in
            imagp.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)

                windowed.withUnsafeBufferPointer { windowedPtr in
                    windowedPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                    }
                }

                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        return magnitudes
    }

    private static func hannWindow(size: Int) -> [Float] {
        var w = [Float](repeating: 0, count: size)
        vDSP_hann_window(&w, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        return w
    }

    // MARK: - Adaptive threshold

    private func adaptiveThreshold() -> Float {
        guard !fluxHistory.isEmpty else { return 0 }
        let mean = fluxHistory.reduce(0, +) / Float(fluxHistory.count)
        return mean * thresholdMultiplier
    }
}
