import Foundation

/// Encodes/decodes the Novation Launchpad X's Programmer Mode SysEx protocol, per
/// Novation's official Launchpad X Programmer's Reference Manual.
///
/// IMPORTANT hardware gotcha (confirmed in the manual): the Launchpad X exposes two USB
/// MIDI port pairs — "LPX DAW In/Out" (Ableton session control) and "LPX MIDI In/Out"
/// (Programmer Mode note/SysEx lighting control, which is what this protocol targets).
/// Device discovery must connect to the "LPX MIDI" pair; the "LPX DAW" pair will silently
/// ignore these messages.
///
/// This type is pure byte math — no CoreMIDI dependency — so it is fully unit-testable.
public enum LaunchpadXProtocol {
    /// Common header for every Launchpad X SysEx message: F0 00 20 29 02 0C <command> ...
    public static let sysExHeader: [UInt8] = [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0C]
    private static let sysExTerminator: UInt8 = 0xF7

    private static let programmerModeCommand: UInt8 = 0x0E
    private static let rgbLightingCommand: UInt8 = 0x03
    private static let rgbColourSpecType: UInt8 = 0x03

    // MARK: - Programmer Mode

    /// Toggles the device between Live mode (its normal standalone/Ableton-session
    /// behavior) and Programmer mode (host-controlled lighting, what this app needs).
    /// Send `enabled: true` on connect and `enabled: false` on disconnect/app-quit so the
    /// device isn't left in a non-standard state.
    public static func programmerModeMessage(enabled: Bool) -> [UInt8] {
        sysExHeader + [programmerModeCommand, enabled ? 0x01 : 0x00, sysExTerminator]
    }

    // MARK: - 8x8 grid <-> Launchpad note number mapping

    /// Maps an (x, y) pixel coordinate (x: 0...7 left->right, y: 0...7 TOP->bottom — the
    /// standard pixel-art/image convention) to the Launchpad's own note number, where the
    /// bottom-left pad is note 11 and the tens digit increases bottom-to-top while the
    /// ones digit increases left-to-right (notes ending in 9/0 fall outside the 8x8 grid —
    /// they're the scene-launch column / top-row function buttons).
    public static func note(x: Int, y: Int) -> UInt8 {
        precondition((0..<8).contains(x) && (0..<8).contains(y), "grid coordinate out of range: (\(x), \(y))")
        let launchpadRow = 8 - y // Launchpad row 1 = bottom, row 8 = top
        let launchpadCol = x + 1
        return UInt8(launchpadRow * 10 + launchpadCol)
    }

    /// Inverse of `note(x:y:)`. Returns nil for note numbers outside the 8x8 grid.
    public static func xy(fromNote note: UInt8) -> (x: Int, y: Int)? {
        let row = Int(note) / 10
        let col = Int(note) % 10
        guard (1...8).contains(row), (1...8).contains(col) else { return nil }
        return (x: col - 1, y: 8 - row)
    }

    // MARK: - RGB frame lighting

    /// Encodes a full 8x8 RGB SysEx frame: F0 00 20 29 02 0C 03 [03 <note> <R> <G> <B>]x64 F7.
    /// R/G/B are Launchpad's native 7-bit range (0...127); `RGBColor.r7/g7/b7` scale down
    /// from the conventional 0...255 range. Fits comfortably in a single SysEx message
    /// (~328 bytes for a full frame) — no chunking required.
    public static func frameMessage(_ grid: PixelGrid) -> [UInt8] {
        var message: [UInt8] = []
        message.reserveCapacity(sysExHeader.count + 1 + PixelGrid.size * PixelGrid.size * 5 + 1)
        message.append(contentsOf: sysExHeader)
        message.append(rgbLightingCommand)
        grid.forEach { x, y, color in
            message.append(contentsOf: [rgbColourSpecType, note(x: x, y: y), color.r7, color.g7, color.b7])
        }
        message.append(sysExTerminator)
        return message
    }

    /// A full-frame message that turns every pad off (black).
    public static func clearAllMessage() -> [UInt8] {
        frameMessage(.allBlack)
    }
}
