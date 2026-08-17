import XCTest
@testable import FaderLabCore

final class RGBColorTests: XCTestCase {

    func test7BitScalingBoundaries() {
        XCTAssertEqual(RGBColor(r: 0, g: 0, b: 0).r7, 0)
        XCTAssertEqual(RGBColor(r: 255, g: 255, b: 255).r7, 127)
    }

    func testHSVPrimaryColors() {
        let red = RGBColor(hue: 0, saturation: 1, value: 1)
        XCTAssertEqual(red, RGBColor(r: 255, g: 0, b: 0))

        let green = RGBColor(hue: 1.0 / 3.0, saturation: 1, value: 1)
        XCTAssertEqual(green, RGBColor(r: 0, g: 255, b: 0))

        let blue = RGBColor(hue: 2.0 / 3.0, saturation: 1, value: 1)
        XCTAssertEqual(blue, RGBColor(r: 0, g: 0, b: 255))
    }

    func testHSVZeroSaturationIsGray() {
        let gray = RGBColor(hue: 0.5, saturation: 0, value: 1)
        XCTAssertEqual(gray, RGBColor(r: 255, g: 255, b: 255))
    }

    func testHSVZeroValueIsBlack() {
        let black = RGBColor(hue: 0.3, saturation: 1, value: 0)
        XCTAssertEqual(black, RGBColor.black)
    }

    func testScaledByFactor() {
        let full = RGBColor(r: 200, g: 100, b: 50)
        XCTAssertEqual(full.scaled(by: 1.0), full)
        XCTAssertEqual(full.scaled(by: 0.0), RGBColor.black)
    }
}
