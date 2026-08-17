import SwiftUI
import UniformTypeIdentifiers

/// A horizontal transport cluster — file picker, play/pause, elapsed time, live BPM, and
/// manual BPM entry all in one row — meant to sit in the fixed `TransportBarView` at the
/// top of the window rather than scroll away with the pattern cards below it.
struct AudioControlView: View {
    @Environment(AppState.self) private var appState
    @State private var manualBPMText = "120"
    @State private var isImporterPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 14) {
                Button("Choose File…") { isImporterPresented = true }
                    .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.audio]) { result in
                        if case .success(let url) = result {
                            appState.loadAudioFile(url: url)
                        }
                    }

                if let url = appState.audioEngine.trackURL {
                    Text(url.lastPathComponent)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 160, alignment: .leading)
                } else {
                    Text("No track loaded")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

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

                Divider().frame(height: 20)

                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Int(appState.audioEngine.currentBPM.rounded())) BPM")
                        .monospacedDigit()
                    Text(isBeatLive ? "Live" : "Free-running")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    Text("Manual BPM").font(.caption)
                    TextField("BPM", text: $manualBPMText)
                        .frame(width: 52)
                        .textFieldStyle(.roundedBorder)
                    Button("Set") {
                        if let bpm = Double(manualBPMText) {
                            appState.audioEngine.setManualBPM(bpm)
                        }
                    }
                    .buttonStyle(.borderless)
                }

                Spacer(minLength: 0)
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
