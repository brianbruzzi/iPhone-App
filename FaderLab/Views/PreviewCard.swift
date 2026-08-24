import SwiftUI

/// Uniform card chrome (title + reset button + rounded card background) shared by the
/// Faders/Launchpad/Surface panels, so the redesigned stage reads as one consistent grid
/// of cards rather than three independently-styled panels.
struct PreviewCard<Content: View>: View {
    let title: String
    let onReset: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button(action: onReset) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CardBackground())
    }
}

#Preview {
    PreviewCard(title: "Example", onReset: {}) {
        Text("Card contents go here")
    }
    .padding()
    .frame(width: 320)
}
