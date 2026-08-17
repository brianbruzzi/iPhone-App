import SwiftUI
import UniformTypeIdentifiers

struct AudioControlView: View {
    @Environment(AppState.self) private var appState
    @State private var manualBPMText = "120"
    @State private var isImporterPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Audio").font(.headline)

            HStack {
                Button("Choose File…") { isImporterPresented = true }
                if let url = appState.audioEngine.trackURL {
                    Text(url.lastPathComponent)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.audio]) { result in
                if case .success(let url) = result {
                    appState.loadAudioFile(url: url)
                }
            }

            HStack(spacing: 16) {
                Button(appState.audioEngine.isPlaying ? "Pause" : "Play") {
                    if appState.audioEngine.isPlaying {
                        appState.audioEngine.pause()
                    } else {
                        appState.audioEngine.play()
                    }
                }
                .disabled(appState.audioEngine.trackURL == nil)

                Text(formattedTime(appState.audioEngine.elapsedSeconds))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(appState.audioEngine.currentBPM.rounded())) BPM")
                        .monospacedDigit()
                    Text(isBeatLive ? "Live" : "Free-running")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Manual BPM")
                TextField("BPM", text: $manualBPMText)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                Button("Set") {
                    if let bpm = Double(manualBPMText) {
                        appState.audioEngine.setManualBPM(bpm)
                    }
                }
            }

            if let error = appState.audioLoadError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var isBeatLive: Bool {
        appState.audioEngine.beatClock.snapshot(now: appState.audioEngine.currentHostTimeSeconds()).isLive
    }

    private func formattedTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#Preview {
    AudioControlView().environment(AppState())
}
