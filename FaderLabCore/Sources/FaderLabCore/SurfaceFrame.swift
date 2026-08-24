import Foundation

/// Text for one scribble strip's two rows.
public struct ScribbleText: Equatable, Sendable {
    public var upper: String
    public var lower: String

    public init(upper: String = "", lower: String = "") {
        self.upper = upper
        self.lower = lower
    }

    public static let blank = ScribbleText()
}

/// One complete surface lighting state — the X-Touch's equivalent of `PixelGrid`: every
/// button LED, every encoder ring, and every scribble strip's color and text, all at once.
public struct SurfaceFrame: Equatable, Sendable {
    /// Parallel to `XTouchSurfaceProtocol.animatableButtonNotes`.
    public var buttons: [XTouchSurfaceProtocol.ButtonLEDState]
    /// Exactly `XTouchSurfaceProtocol.stripCount` entries.
    public var rings: [XTouchSurfaceProtocol.RingDisplay]
    /// Exactly `XTouchSurfaceProtocol.stripCount` entries.
    public var scribbleColors: [XTouchSurfaceProtocol.ScribbleColor]
    /// Exactly `XTouchSurfaceProtocol.stripCount` entries.
    public var scribbleTexts: [ScribbleText]

    public init(
        buttons: [XTouchSurfaceProtocol.ButtonLEDState],
        rings: [XTouchSurfaceProtocol.RingDisplay],
        scribbleColors: [XTouchSurfaceProtocol.ScribbleColor],
        scribbleTexts: [ScribbleText]
    ) {
        precondition(buttons.count == XTouchSurfaceProtocol.animatableButtonNotes.count)
        precondition(rings.count == XTouchSurfaceProtocol.stripCount)
        precondition(scribbleColors.count == XTouchSurfaceProtocol.stripCount)
        precondition(scribbleTexts.count == XTouchSurfaceProtocol.stripCount)
        self.buttons = buttons
        self.rings = rings
        self.scribbleColors = scribbleColors
        self.scribbleTexts = scribbleTexts
    }

    public static let allOff = SurfaceFrame(
        buttons: Array(repeating: .off, count: XTouchSurfaceProtocol.animatableButtonNotes.count),
        rings: Array(repeating: .off, count: XTouchSurfaceProtocol.stripCount),
        scribbleColors: Array(repeating: .black, count: XTouchSurfaceProtocol.stripCount),
        scribbleTexts: Array(repeating: .blank, count: XTouchSurfaceProtocol.stripCount)
    )

    /// Reads/writes a button's LED state by hardware note number. An unknown note reads
    /// as `.off` and ignores writes — there's nowhere in the frame to store it.
    public subscript(buttonNote note: UInt8) -> XTouchSurfaceProtocol.ButtonLEDState {
        get {
            guard let index = XTouchSurfaceProtocol.buttonIndex(forNote: note) else { return .off }
            return buttons[index]
        }
        set {
            guard let index = XTouchSurfaceProtocol.buttonIndex(forNote: note) else { return }
            buttons[index] = newValue
        }
    }

    /// Sets every button note in `zone` to `state`.
    public mutating func fill(_ zone: XTouchSurfaceProtocol.ButtonZone, with state: XTouchSurfaceProtocol.ButtonLEDState) {
        for note in zone.notes {
            self[buttonNote: note] = state
        }
    }
}

/// Computes the minimal set of MIDI messages needed to take the hardware from one
/// `SurfaceFrame` to another — the surface analogue of the Launchpad's frame-dedup cache
/// in `MIDIManager`, but expressed as pure, testable logic rather than living inline in
/// the send path.
public enum XTouchSurfaceDiff {
    /// `old` = nil means the hardware's actual state is unknown (first frame, or after
    /// anything that could have changed it out-of-band), so a full repaint is emitted.
    /// Equal frames emit nothing.
    public static func messages(from old: SurfaceFrame?, to new: SurfaceFrame) -> [[UInt8]] {
        guard let old else { return fullRepaint(new) }
        guard old != new else { return [] }

        var messages: [[UInt8]] = []

        for (index, note) in XTouchSurfaceProtocol.animatableButtonNotes.enumerated()
        where old.buttons[index] != new.buttons[index] {
            messages.append(XTouchSurfaceProtocol.buttonLEDBytes(note: note, state: new.buttons[index]))
        }

        for strip in 0..<XTouchSurfaceProtocol.stripCount where old.rings[strip] != new.rings[strip] {
            messages.append(XTouchSurfaceProtocol.ringBytes(strip: strip, display: new.rings[strip]))
        }

        // Colors are all-or-nothing on the wire — one message covers all 8 strips.
        if old.scribbleColors != new.scribbleColors {
            messages.append(XTouchSurfaceProtocol.scribbleColorsMessage(new.scribbleColors))
        }

        for strip in 0..<XTouchSurfaceProtocol.stripCount {
            if old.scribbleTexts[strip].upper != new.scribbleTexts[strip].upper {
                messages.append(
                    XTouchSurfaceProtocol.scribbleTextMessage(strip: strip, row: .upper, text: new.scribbleTexts[strip].upper)
                )
            }
            if old.scribbleTexts[strip].lower != new.scribbleTexts[strip].lower {
                messages.append(
                    XTouchSurfaceProtocol.scribbleTextMessage(strip: strip, row: .lower, text: new.scribbleTexts[strip].lower)
                )
            }
        }

        return messages
    }

    private static func fullRepaint(_ frame: SurfaceFrame) -> [[UInt8]] {
        var messages: [[UInt8]] = []

        for (index, note) in XTouchSurfaceProtocol.animatableButtonNotes.enumerated() {
            messages.append(XTouchSurfaceProtocol.buttonLEDBytes(note: note, state: frame.buttons[index]))
        }
        for strip in 0..<XTouchSurfaceProtocol.stripCount {
            messages.append(XTouchSurfaceProtocol.ringBytes(strip: strip, display: frame.rings[strip]))
        }
        messages.append(XTouchSurfaceProtocol.scribbleColorsMessage(frame.scribbleColors))
        for strip in 0..<XTouchSurfaceProtocol.stripCount {
            messages.append(XTouchSurfaceProtocol.scribbleTextMessage(strip: strip, row: .upper, text: frame.scribbleTexts[strip].upper))
            messages.append(XTouchSurfaceProtocol.scribbleTextMessage(strip: strip, row: .lower, text: frame.scribbleTexts[strip].lower))
        }

        return messages
    }
}
