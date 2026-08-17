import SwiftUI

@main
struct FaderLabApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onAppear { appState.start() }
                .onDisappear { appState.stop() }
        }
        .windowResizability(.contentSize)
    }
}
