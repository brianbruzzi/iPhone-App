import SwiftUI

/// The Playback menu: keyboard control over the show and the track for live use.
///
/// Shortcut choices are deliberate about conflicts: no bare Space (menu key-equivalents
/// are matched before text fields see keystrokes, so bare Space would swallow the spaces
/// typed into the Display Text field), no ⌘P (Print), no ⌘T (window-tabbing's New Tab).
/// Titles are static "X/Y" pairs rather than live state — menu items don't reliably
/// re-render on @Observable changes, and a stale title is worse than a neutral one.
struct PlaybackCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandMenu("Playback") {
            Button("Pause/Resume Show") {
                appState.togglePatternPause()
            }
            .keyboardShortcut(.space, modifiers: [.command, .shift])

            Divider()

            Button("Play/Pause Track") {
                if appState.audioEngine.isPlaying {
                    appState.audioEngine.pause()
                } else {
                    appState.audioEngine.play()
                }
            }
            .keyboardShortcut(.return, modifiers: .command)

            Button("Restart Track") {
                appState.audioEngine.restartFromBeginning()
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Stop Track") {
                appState.audioEngine.stop()
            }
            .keyboardShortcut(".", modifiers: .command)

            Button("Toggle Loop") {
                appState.toggleLooping()
            }
            .keyboardShortcut("l", modifiers: .command)

            Button("Tap Tempo") {
                appState.tapTempo()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Divider()

            Button("Setup & Diagnostics") {
                appState.showDiagnostics.toggle()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }
    }
}
