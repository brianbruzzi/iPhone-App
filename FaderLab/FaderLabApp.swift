import SwiftUI

@main
struct FaderLabApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                // Committed dark "stage" look — this app controls stage lighting, and the
                // UI always reads as lit hardware on a dark stage regardless of the
                // system appearance. Applied here so sheets/inspectors inherit it too.
                .preferredColorScheme(.dark)
                .onAppear { appState.start() }
                .onDisappear { appState.stop() }
        }
        // Designed for a 1920x1080 frame with zero scrolling; still freely resizable
        // above the content minimum ContentView declares.
        .defaultSize(width: 1920, height: 1080)
        .windowResizability(.contentMinSize)
        .commands {
            PlaybackCommands(appState: appState)
        }
    }
}
