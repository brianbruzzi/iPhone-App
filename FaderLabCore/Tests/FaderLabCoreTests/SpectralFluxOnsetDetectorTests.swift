import XCTest
@testable import FaderLabCore

final class SpectralFluxOnsetDetectorTests: XCTestCase {
    private let sampleRate = 44100.0
    private let fftSize = 1024

    private func sineFrame(frequency: Double, amplitude: Float, count: Int) -> [Float] {
        (0..<count).map { i in
            amplitude * Float(sin(2 * Double.pi * frequency * Double(i) / sampleRate))
        }
    }

    func testDetectsOnsetAtSilenceToToneTransition() {
        let detector = SpectralFluxOnsetDetector(sampleRate: sampleRate, fftSize: fftSize)
        let frameDuration = Double(fftSize) / sampleRate
        let silentFrame = [Float](repeating: 0, count: fftSize)
        let toneFrame = sineFrame(frequency: 440, amplitude: 0.8, count: fftSize)

        // A few silent frames, then a sustained tone starting — spectral flux should spike
        // exactly once, at the transition, since a held steady tone has ~zero frame-to-frame flux.
        let frames: [[Float]] = Array(repeating: silentFrame, count: 5) + Array(repeating: toneFrame, count: 5)

        var detectedTimes: [TimeInterval] = []
        for (index, frame) in frames.enumerated() {
            let t = Double(index) * frameDuration
            detectedTimes.append(contentsOf: detector.process(samples: frame, timeSeconds: t).map { $0.timeSeconds })
        }

        XCTAssertEqual(detectedTimes.count, 1, "expected exactly one onset, at the silence->tone transition")
        XCTAssertEqual(detectedTimes.first ?? -1, 5 * frameDuration, accuracy: 1e-9)
    }

    func testDebounceSuppressesRapidRepeatedOnsets() {
        let detector = SpectralFluxOnsetDetector(sampleRate: sampleRate, fftSize: fftSize, minInterOnsetInterval: 1.0)
        let frameDuration = Double(fftSize) / sampleRate
        let silentFrame = [Float](repeating: 0, count: fftSize)
        let toneFrame = sineFrame(frequency: 440, amplitude: 0.8, count: fftSize)

        // silence, tone-onset, silence, tone-onset-again — the second transition arrives
        // well within the 1-second debounce window.
        let frames: [[Float]] = [silentFrame, toneFrame, silentFrame, toneFrame]

        var onsetCount = 0
        for (index, frame) in frames.enumerated() {
            let t = Double(index) * frameDuration
            onsetCount += detector.process(samples: frame, timeSeconds: t).count
        }

        XCTAssertEqual(onsetCount, 1)
    }

    func testSilenceProducesNoOnsets() {
        let detector = SpectralFluxOnsetDetector(sampleRate: sampleRate, fftSize: fftSize)
        let frameDuration = Double(fftSize) / sampleRate
        let silentFrame = [Float](repeating: 0, count: fftSize)

        var onsetCount = 0
        for index in 0..<20 {
            let t = Double(index) * frameDuration
            onsetCount += detector.process(samples: silentFrame, timeSeconds: t).count
        }

        XCTAssertEqual(onsetCount, 0)
    }

    func testShortBufferIsZeroPaddedNotCrashing() {
        let detector = SpectralFluxOnsetDetector(sampleRate: sampleRate, fftSize: fftSize)
        let shortFrame = sineFrame(frequency: 440, amplitude: 0.8, count: fftSize / 4)
        XCTAssertNoThrow(_ = detector.process(samples: shortFrame, timeSeconds: 0))
    }

    func testOversizedBufferIsTruncatedNotCrashing() {
        let detector = SpectralFluxOnsetDetector(sampleRate: sampleRate, fftSize: fftSize)
        let longFrame = sineFrame(frequency: 440, amplitude: 0.8, count: fftSize * 2)
        XCTAssertNoThrow(_ = detector.process(samples: longFrame, timeSeconds: 0))
    }
}
