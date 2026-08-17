import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
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

                HStack {
                    MasterSyncToggle()
                    Spacer()
                    Button {
                        appState.resetAll()
                    } label: {
                        Label("Reset Everything to Defaults", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 760, minHeight: 640)
    }
}

#Preview {
    ContentView().environment(AppState())
}
