import Foundation

/// An 8-bit-per-channel RGB color. Pure value type — no dependency on AppKit/SwiftUI
/// so it can be used identically in pattern generators, protocol encoders, and tests.
public struct RGBColor: Equatable, Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public static let black = RGBColor(r: 0, g: 0, b: 0)
    public static let white = RGBColor(r: 255, g: 255, b: 255)

    /// Launchpad X SysEx colour bytes are 7-bit (0...127), not 8-bit. Scale down from 0...255.
    public var r7: UInt8 { RGBColor.scale8To7(r) }
    public var g7: UInt8 { RGBColor.scale8To7(g) }
    public var b7: UInt8 { RGBColor.scale8To7(b) }

    private static func scale8To7(_ value: UInt8) -> UInt8 {
        UInt8((Int(value) * 127 + 127) / 255)
    }

    /// hue/saturation/value all in 0...1. Standard HSV->RGB conversion, used by the
    /// plasma/rainbow pixel-art patterns which are naturally expressed in HSV space.
    public init(hue: Double, saturation: Double, value: Double) {
        let h = hue - floor(hue)
        let s = min(max(saturation, 0), 1)
        let v = min(max(value, 0), 1)

        let i = Int(h * 6)
        let f = h * 6 - Double(i)
        let p = v * (1 - s)
        let q = v * (1 - f * s)
        let t = v * (1 - (1 - f) * s)

        let (rf, gf, bf): (Double, Double, Double)
        switch i % 6 {
        case 0: (rf, gf, bf) = (v, t, p)
        case 1: (rf, gf, bf) = (q, v, p)
        case 2: (rf, gf, bf) = (p, v, t)
        case 3: (rf, gf, bf) = (p, q, v)
        case 4: (rf, gf, bf) = (t, p, v)
        default: (rf, gf, bf) = (v, p, q)
        }

        self.r = UInt8(min(max(rf, 0), 1) * 255)
        self.g = UInt8(min(max(gf, 0), 1) * 255)
        self.b = UInt8(min(max(bf, 0), 1) * 255)
    }

    /// Scales brightness by a 0...1 factor, clamping each channel.
    public func scaled(by factor: Double) -> RGBColor {
        let f = min(max(factor, 0), 1)
        return RGBColor(
            r: UInt8(Double(r) * f),
            g: UInt8(Double(g) * f),
            b: UInt8(Double(b) * f)
        )
    }
}
