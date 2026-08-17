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

    // MARK: - Registry

    func testRegistryContainsAllBuiltInPatterns() {
        let ids = Set(PadPatterns.all.map { type(of: $0).id })
        XCTAssertEqual(ids, ["plasmaWave", "rainbowChase", "beatRipple", "vuColumns"])
    }
}
