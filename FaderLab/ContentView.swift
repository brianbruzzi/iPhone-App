import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DeviceStatusView()

            Divider()

            HStack(alignment: .top, spacing: 24) {
                FaderControlView()
                LaunchpadControlView()
            }

            Divider()

            AudioControlView()

            Divider()

            MasterSyncToggle()
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 520)
    }
}

#Preview {
    ContentView().environment(AppState())
}
