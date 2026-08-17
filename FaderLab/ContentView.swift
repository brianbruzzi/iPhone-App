import SwiftUI

struct ContentView: View {
    private let cardColumns = [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: 20)]

    var body: some View {
        VStack(spacing: 0) {
            TransportBarView()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LazyVGrid(columns: cardColumns, alignment: .leading, spacing: 20) {
                        FaderControlView()
                        LaunchpadControlView()
                        SurfaceControlView()
                    }

                    DeviceStatusView()

                    DiagnosticsView()
                }
                .padding(20)
            }
        }
        .frame(minWidth: 900, minHeight: 820)
    }
}

#Preview {
    ContentView().environment(AppState())
}
