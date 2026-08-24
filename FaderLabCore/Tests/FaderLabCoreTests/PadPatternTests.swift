import XCTest
@testable import FaderLabCore

final class PadPatternTests: XCTestCase {

    // MARK: - Plasma wave

    func testPlasmaWaveZeroBrightnessIsAllBlack() {
        let params = PadPatternParams(speed: 1, hueShift: 0, brightness: 0)
        let grid = PlasmaWavePattern().render(elapsed: 1.5, beat: .idle, params: params)
        XCTAssertEqual(grid, .allBlack)
    }

    func testPlasmaWaveIsDeterministic() {
        let params = PadPatternParams(speed: 1, hueShift: 0.2, brightness: 0.8)
        let gridA = PlasmaWavePattern().render(elapsed: 2.0, beat: .idle, params: params)
        let gridB = PlasmaWavePattern().render(elapsed: 2.0, beat: .idle, params: params)
        XCTAssertEqual(gridA, gridB)
    }

    // MARK: - Rainbow chase

    func testRainbowChaseTopLeftIsRedAtOrigin() {
        let params = PadPatternParams(speed: 1, hueShift: 0, brightness: 1)
        let grid = RainbowChasePattern().render(elapsed: 0, beat: .idle, params: params)
        XCTAssertEqual(grid[0, 0], RGBColor(hue: 0, saturation: 1, value: 1))
    }

    func testRainbowChaseZeroBrightnessIsAllBlack() {
        let params = PadPatternParams(speed: 1, hueShift: 0.4, brightness: 0)
        let grid = RainbowChasePattern().render(elapsed: 3.3, beat: .idle, params: params)
        XCTAssertEqual(grid, .allBlack)
    }

    // MARK: - Beat ripple

    func testBeatRippleLitNearCenterAtBeatOnset() {
        let params = PadPatternParams(speed: 1, hueShift: 0, brightness: 1)
        let beat = BeatClockSnapshot(bpm: 120, phase: 0, beatIndex: 0, isLive: true)
        let grid = BeatRipplePattern().render(elapsed: 0, beat: beat, params: params)
        XCTAssertNotEqual(grid[3, 3], .black, "a pad near the center should be lit right at the beat onset")
    }

    func testBeatRippleFarCornerUnlitAtBeatOnset() {
        let params = PadPatternParams(speed: 1, hueShift: 0, brightness: 1)
        let beat = BeatClockSnapshot(bpm: 120, phase: 0, beatIndex: 0, isLive: true)
        let grid = BeatRipplePattern().render(elapsed: 0, beat: beat, params: params)
        XCTAssertEqual(grid[0, 0], .black, "the ring hasn't expanded out to the corner yet")
    }

    func testBeatRippleFullyFadedIsAllBlack() {
        let params = PadPatternParams(speed: 1, hueShift: 0, brightness: 1)
        // Slow tempo + late beat phase => large elapsed-since-beat => fully faded.
        let beat = BeatClockSnapshot(bpm: 30, phase: 0.9, beatIndex: 0, isLive: true)
        let grid = BeatRipplePattern().render(elapsed: 0, beat: beat, params: params)
        XCTAssertEqual(grid, .allBlack)
    }

    // MARK: - VU columns

    func testVUColumnsSilentIsAllBlack() {
        let params = PadPatternParams(speed: 1, hueShift: 0, brightness: 1, audioLevel: 0)
        let grid = VUMeterColumnsPattern().render(elapsed: 0, beat: .idle, params: params)
        XCTAssertEqual(grid, .allBlack)
    }

    func testVUColumnsLoudLightsBottomRowGreenish() {
        let params = PadPatternParams(speed: 1, hueShift: 0, brightness: 1, audioLevel: 1)
        let grid = VUMeterColumnsPattern().render(elapsed: 0, beat: .idle, params: params)
        let bottomLeft = grid[0, 7]
        XCTAssertNotEqual(bottomLeft, .black)
        XCTAssertGreaterThan(bottomLeft.g, bottomLeft.r, "low VU height should read as green-dominant, not red")
    }

    // MARK: - Sparkle

    func testSparkleZeroBrightnessIsAllBlack() {
        let params = PadPatternParams(speed: 1, hueShift: 0, brightness: 0)
        let grid = SparklePattern().render(elapsed: 1.7, beat: .idle, params: params)
        XCTAssertEqual(grid, .allBlack)
    }

    func testSparkleIsDeterministicAndSparse() {
        let params = PadPatternParams(speed: 1, hueShift: 0, brightness: 1)
        let gridA = SparklePattern().render(elapsed: 5.0, beat: .idle, params: params)
        let gridB = SparklePattern().render(elapsed: 5.0, beat: .idle, params: params)
        XCTAssertEqual(gridA, gridB)

        // "Sparse twinkling" means most pads should be off at any given instant, not the
        // whole grid lit at once.
        var litCount = 0
        gridA.forEach { _, _, color in if color != .black { litCount += 1 } }
        XCTAssertLessThan(litCount, 64)
    }

    // MARK: - Bouncing ball

    func testBouncingBallZeroBrightnessIsAllBlack() {
        let params = PadPatternParams(speed: 1, hueShift: 0, brightness: 0)
        let grid = BouncingBallPattern().render(elapsed: 0.9, beat: .idle, params: params)
        XCTAssertEqual(grid, .allBlack)
    }

    func testBouncingBallHasABrightSpotSomewhereOnTheGrid() {
        let params = PadPatternParams(speed: 1, hueShift: 0, brightness: 1)
        let grid = BouncingBallPattern().render(elapsed: 0, beat: .idle, params: params)
        var sawLitPad = false
        grid.forEach { _, _, color in if color != .black { sawLitPad = true } }
        XCTAssertTrue(sawLitPad)
    }

    func testBouncingBallIsDeterministic() {
        let params = PadPatternParams()
        let gridA = BouncingBallPattern().render(elapsed: 3.14, beat: .idle, params: params)
        let gridB = BouncingBallPattern().render(elapsed: 3.14, beat: .idle, params: params)
        XCTAssertEqual(gridA, gridB)
    }

    // MARK: - Ember fire

    func testEmberFireZeroBrightnessIsAllBlack() {
        let params = PadPatternParams(speed: 1, hueShift: 0, brightness: 0)
        let grid = EmberFirePattern().render(elapsed: 1.2, beat: .idle, params: params)
        XCTAssertEqual(grid, .allBlack)
    }

    func testEmberFireBottomRowLitBrighterThanTop() {
        let params = PadPatternParams(speed: 1, hueShift: 0, brightness: 1)
        let grid = EmberFirePattern().render(elapsed: 0, beat: .idle, params: params)
        // Every column's flame reaches at least partway up, so the base row should never
        // be black, while the very top row (a flame height of ~7) is only lit on the
        // tallest flicker peaks — not guaranteed lit at every instant.
        for x in 0..<8 {
            XCTAssertNotEqual(grid[x, 7], .black, "column \(x)'s base should always be lit")
        }
    }

    func testEmberFireIsDeterministic() {
        let params = PadPatternParams(speed: 1, hueShift: 0.1, brightness: 1)
        let gridA = EmberFirePattern().render(elapsed: 4.4, beat: .idle, params: params)
        let gridB = EmberFirePattern().render(elapsed: 4.4, beat: .idle, params: params)
        XCTAssertEqual(gridA, gridB)
    }

    // MARK: - Strobe pulse

    func testStrobePulseFlashesBrightRightOnTheBeat() {
        let params = PadPatternParams(speed: 1, hueShift: 0, brightness: 1)
        let beat = BeatClockSnapshot(bpm: 120, phase: 0, beatIndex: 0, isLive: true)
        let grid = StrobePulsePattern().render(elapsed: 0, beat: beat, params: params)
        XCTAssertNotEqual(grid[0, 0], .black)
        XCTAssertEqual(grid, PixelGrid(repeating: grid[0, 0]), "the strobe flash should cover every pad uniformly")
    }

    func testStrobePulseFadesToBlackLateInTheBeat() {
        let params = PadPatternParams(speed: 1, hueShift: 0, brightness: 1)
        let beat = BeatClockSnapshot(bpm: 120, phase: 0.99, beatIndex: 0, isLive: true)
        let grid = StrobePulsePattern().render(elapsed: 0, beat: beat, params: params)
        XCTAssertEqual(grid, .allBlack)
    }

    func testStrobePulseZeroBrightnessIsAllBlack() {
        let params = PadPatternParams(speed: 1, hueShift: 0, brightness: 0)
        let beat = BeatClockSnapshot(bpm: 120, phase: 0, beatIndex: 0, isLive: true)
        let grid = StrobePulsePattern().render(elapsed: 0, beat: beat, params: params)
        XCTAssertEqual(grid, .allBlack)
    }

    // MARK: - Spiral sweep

    func testSpiralSweepZeroBrightnessIsAllBlack() {
        let params = PadPatternParams(speed: 1, hueShift: 0, brightness: 0)
        let grid = SpiralSweepPattern().render(elapsed: 2.5, beat: .idle, params: params)
        XCTAssertEqual(grid, .allBlack)
    }

    func testSpiralSweepIsDeterministic() {
        let params = PadPatternParams(speed: 1, hueShift: 0.3, brightness: 1)
        let gridA = SpiralSweepPattern().render(elapsed: 6.0, beat: .idle, params: params)
        let gridB = SpiralSweepPattern().render(elapsed: 6.0, beat: .idle, params: params)
        XCTAssertEqual(gridA, gridB)
    }

    // MARK: - VB Eye

    func testVBEyeOpenIsSymmetricTopToBottomWithColorSwap() {
        let params = PadPatternParams(speed: 1, hueShift: 0.5, brightness: 1) // hueShift ignored
        let grid = VBEyePattern().render(elapsed: 1.0, beat: .idle, params: params) // outside the blink window

        // Corners: yellow up top, red on the bottom — the brand mark's color split.
        XCTAssertEqual(grid[2, 0], RGBColor(r: 225, g: 200, b: 50))
        XCTAssertEqual(grid[2, 7], RGBColor(r: 200, g: 75, b: 50))
        // The iris/pupil pair at the true center is identical on both middle rows.
        XCTAssertEqual(grid[2, 3], grid[2, 4])
        XCTAssertEqual(grid[3, 3], .black, "pupil should be black")
    }

    func testVBEyeBlinksBrieflyThenReopens() {
        let params = PadPatternParams(speed: 1, hueShift: 0, brightness: 1)
        let blinking = VBEyePattern().render(elapsed: 0.0, beat: .idle, params: params)
        let open = VBEyePattern().render(elapsed: 1.0, beat: .idle, params: params)

        XCTAssertEqual(blinking[0, 0], .black)
        XCTAssertEqual(blinking[0, 3], .black, "eyelid seam starts a column in, not at the very edge")
        XCTAssertNotEqual(open[2, 0], .black, "should be back to the open eye a second later")
    }

    func testVBEyeZeroBrightnessIsAllBlack() {
        let params = PadPatternParams(speed: 1, hueShift: 0, brightness: 0)
        let grid = VBEyePattern().render(elapsed: 1.0, beat: .idle, params: params)
        XCTAssertEqual(grid, .allBlack)
    }

    // MARK: - Registry

    func testRegistryContainsAllBuiltInPatterns() {
        let ids = Set(PadPatterns.all.map { type(of: $0).id })
        XCTAssertEqual(ids, [
            "plasmaWave", "rainbowChase", "beatRipple", "vuColumns", "sparkle", "bouncingBall",
            "emberFire", "strobePulse", "spiralSweep", "vbEye"
        ])
    }
}
