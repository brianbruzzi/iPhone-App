import SwiftUI

/// The app's committed "dark stage" palette. FaderLab controls stage lighting hardware, so
/// the UI ignores the system appearance and always renders as a dark stage with lit
/// hardware on it (`.preferredColorScheme(.dark)` is applied at the root in FaderLabApp).
/// Everything here is deliberately opaque — vibrancy materials would let the desktop bleed
/// through and fight the committed look.
enum Theme {
    /// The room: near-black, warmed slightly off pure black so surfaces can sit above it.
    static let stage = Color(red: 0.039, green: 0.039, blue: 0.047) // #0A0A0C
    /// Transport bar and status strip — the fixed chrome, one step above the stage.
    static let raisedBar = Color(red: 0.063, green: 0.063, blue: 0.078) // #101014
    /// Card surfaces, one more step up.
    static let cardSurface = Color(red: 0.078, green: 0.082, blue: 0.094) // #141518
    /// The "wells" the three live hardware previews sit in — darker than the stage, so
    /// the lit elements inside read as the brightest thing on screen.
    static let previewWell = Color(red: 0.016, green: 0.016, blue: 0.024) // #040406
    /// Hairline strokes on cards and bars.
    static let hairline = Color.white.opacity(0.08)
    /// The master fader bar. White-hot rather than accent amber, so master stays visually
    /// distinct now that the accent color is itself a warm amber.
    static let masterFader = Color.white.opacity(0.92)
}

/// Card chrome for the dark stage: lifted surface, hairline edge, soft drop shadow.
/// Replaces the old `.quaternary` material background in `PreviewCard`.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline))
            .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
    }
}

/// Small-caps section label used inside cards ("FADERS", "METERS & DISPLAY", ...).
/// Promoted from a private helper in the old XTouchControlView so all cards share it.
struct SectionHeader: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }
}
