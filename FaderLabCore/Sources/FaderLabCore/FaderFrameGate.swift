import Foundation

/// Delta-gates outgoing fader position messages so the same encoded value is never sent
/// twice in a row. This is the fix for the motorized faders' audible "buzz" at rest: the
/// X-Touch's servo re-seeks every time it receives a position command, even when that
/// command repeats the position it's already at, so re-sending an unchanged target on
/// every animation tick makes the motor visibly/audibly hunt in place.
///
/// Important: the X-Touch also emits pitch-bend/CC messages as live position *feedback*
/// while a fader is moving (motor- or hand-driven) — see `XTouchProtocol`'s doc comment.
/// Those inbound reports must never invalidate this cache; doing so would reintroduce the
/// exact buzz this type exists to remove, since every outbound send would then race an
/// inbound echo of itself. Only call `invalidate`/`invalidateAll` for things that make the
/// cache actively wrong: touch release (a fresh automated value should always land),
/// manual destination/mode changes, diagnostic test sends that bypass this gate, and reset.
public final class FaderFrameGate {
    private var lastSentEncoded: [Int?]
    private var lastMode: SurfaceMode?

    public init(faderCount: Int = XTouchProtocol.faderCount) {
        lastSentEncoded = Array(repeating: nil, count: faderCount)
    }

    /// Encodes `faders` (0...1 unit values; `.nan` entries are skipped, matching
    /// `PatternEngine`'s convention for "hand is on this fader, don't touch it") against
    /// `mode`, returning only the messages whose encoded value actually changed since the
    /// last call. A mode change flushes the whole cache first, since the two modes' wire
    /// formats aren't comparable. `.hui` is never supported, so it always yields `[]`.
    public func messages(for faders: [Double], mode: SurfaceMode) -> [[UInt8]] {
        guard mode.isSupported else {
            lastMode = mode
            return []
        }

        if mode != lastMode {
            lastMode = mode
            invalidateAll()
        }

        if faders.count != lastSentEncoded.count {
            lastSentEncoded = Array(repeating: nil, count: faders.count)
        }

        var messages: [[UInt8]] = []
        for (index, unitValue) in faders.enumerated() where unitValue.isFinite {
            let encoded: Int
            let bytes: [UInt8]
            switch mode {
            case .mackieControl:
                encoded = XTouchProtocol.value14(fromUnit: unitValue)
                bytes = XTouchProtocol.pitchBendBytes(fader: index, value14: encoded)
            case .ctrl:
                encoded = XTouchCtrlProtocol.value7(fromUnit: unitValue)
                bytes = XTouchCtrlProtocol.faderBytes(fader: index, value7: encoded)
            case .hui:
                continue
            }

            guard lastSentEncoded[index] != encoded else { continue }
            lastSentEncoded[index] = encoded
            messages.append(bytes)
        }
        return messages
    }

    /// Forces the next `messages(for:mode:)` call to re-send `fader`'s current value,
    /// regardless of whether it matches the cache.
    public func invalidate(fader: Int) {
        guard lastSentEncoded.indices.contains(fader) else { return }
        lastSentEncoded[fader] = nil
    }

    /// Forces the next `messages(for:mode:)` call to re-send every fader's current value.
    public func invalidateAll() {
        for index in lastSentEncoded.indices {
            lastSentEncoded[index] = nil
        }
    }
}
