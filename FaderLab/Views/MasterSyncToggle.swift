import SwiftUI

struct MasterSyncToggle: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Toggle("Sync patterns to the beat", isOn: $appState.syncToBeat)
            .toggleStyle(.switch)
            .help("When off, patterns run on free-running time only — useful for previewing them without audio.")
    }
}

#Preview {
    MasterSyncToggle().environment(AppState())
}
