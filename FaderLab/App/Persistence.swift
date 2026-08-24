import Foundation
import FaderLabCore

/// Settings persistence: every user-facing knob survives relaunch, stored as one flat
/// dictionary under a single versioned UserDefaults key.
///
/// The one rule that matters: **loading must happen in a method call, never in `init`** —
/// Swift doesn't fire `didSet` for assignments made during initialization, and the didSets
/// are exactly what push each value into the pattern engine and MIDI layer. `start()`
/// calls `loadPersistedSettings()` before anything else.
extension AppState {
    private static let settingsKey = "FaderLabSettings.v1"

    private enum Key {
        static let faderPatternID = "faderPatternID"
        static let faderAmplitude = "faderAmplitude"
        static let faderBaseLevel = "faderBaseLevel"
        static let padPatternID = "padPatternID"
        static let padSpeed = "padSpeed"
        static let padHueShift = "padHueShift"
        static let padBrightness = "padBrightness"
        static let padRotation = "padRotation"
        static let surfacePatternID = "surfacePatternID"
        static let surfaceIntensity = "surfaceIntensity"
        static let surfaceReversed = "surfaceReversed"
        static let rightSectionPatternID = "rightSectionPatternID"
        static let rightSectionIntensity = "rightSectionIntensity"
        static let xTouchSpeed = "xTouchSpeed"
        static let vuMeterSource = "vuMeterSource"
        static let displayText = "displayText"
        static let syncToBeat = "syncToBeat"
        static let isLooping = "isLooping"
    }

    /// Writes the full settings snapshot. Called from every user-facing didSet — writes
    /// are in-memory and coalesced by UserDefaults, so slider-drag frequency is fine.
    func persistSettings() {
        guard !isLoadingSettings else { return }
        let snapshot: [String: Any] = [
            Key.faderPatternID: faderPatternID,
            Key.faderAmplitude: faderAmplitude,
            Key.faderBaseLevel: faderBaseLevel,
            Key.padPatternID: padPatternID,
            Key.padSpeed: padSpeed,
            Key.padHueShift: padHueShift,
            Key.padBrightness: padBrightness,
            Key.padRotation: padRotation.persistenceKey,
            Key.surfacePatternID: surfacePatternID,
            Key.surfaceIntensity: surfaceIntensity,
            Key.surfaceReversed: surfaceReversed,
            Key.rightSectionPatternID: rightSectionPatternID,
            Key.rightSectionIntensity: rightSectionIntensity,
            Key.xTouchSpeed: xTouchSpeed,
            Key.vuMeterSource: vuMeterSource.rawValue,
            Key.displayText: displayText,
            Key.syncToBeat: syncToBeat,
            Key.isLooping: audioEngine.isLooping
        ]
        UserDefaults.standard.set(snapshot, forKey: AppState.settingsKey)
    }

    /// Restores the last-saved settings. Missing or unrecognized entries silently keep
    /// their defaults (`apply*Pattern()` already guards unknown pattern ids, and a removed
    /// enum case just fails its lookup). Guarded so a second `start()` after `stop()`
    /// doesn't stomp live values.
    func loadPersistedSettings() {
        guard !hasLoadedSettings else { return }
        hasLoadedSettings = true
        guard let snapshot = UserDefaults.standard.dictionary(forKey: AppState.settingsKey) else { return }

        isLoadingSettings = true
        defer { isLoadingSettings = false }

        if let value = snapshot[Key.faderPatternID] as? String { faderPatternID = value }
        if let value = snapshot[Key.faderAmplitude] as? Double { faderAmplitude = value }
        if let value = snapshot[Key.faderBaseLevel] as? Double { faderBaseLevel = value }
        if let value = snapshot[Key.padPatternID] as? String { padPatternID = value }
        if let value = snapshot[Key.padSpeed] as? Double { padSpeed = value }
        if let value = snapshot[Key.padHueShift] as? Double { padHueShift = value }
        if let value = snapshot[Key.padBrightness] as? Double { padBrightness = value }
        if let raw = snapshot[Key.padRotation] as? String,
           let rotation = GridRotation(persistenceKey: raw) { padRotation = rotation }
        if let value = snapshot[Key.surfacePatternID] as? String { surfacePatternID = value }
        if let value = snapshot[Key.surfaceIntensity] as? Double { surfaceIntensity = value }
        if let value = snapshot[Key.surfaceReversed] as? Bool { surfaceReversed = value }
        if let value = snapshot[Key.rightSectionPatternID] as? String { rightSectionPatternID = value }
        if let value = snapshot[Key.rightSectionIntensity] as? Double { rightSectionIntensity = value }
        if let value = snapshot[Key.xTouchSpeed] as? Double { xTouchSpeed = value }
        if let raw = snapshot[Key.vuMeterSource] as? String,
           let source = VUMeterSource(rawValue: raw) { vuMeterSource = source }
        if let value = snapshot[Key.displayText] as? String { displayText = value }
        if let value = snapshot[Key.syncToBeat] as? Bool { syncToBeat = value }
        if let value = snapshot[Key.isLooping] as? Bool { audioEngine.isLooping = value }
    }
}

/// `GridRotation` lives in FaderLabCore and isn't RawRepresentable; this app-layer mapping
/// gives it a stable string form for persistence without touching the Core type.
extension GridRotation {
    var persistenceKey: String {
        switch self {
        case .degrees0: return "degrees0"
        case .degrees90: return "degrees90"
        case .degrees180: return "degrees180"
        case .degrees270: return "degrees270"
        }
    }

    init?(persistenceKey: String) {
        guard let match = GridRotation.allCases.first(where: { $0.persistenceKey == persistenceKey }) else {
            return nil
        }
        self = match
    }
}
