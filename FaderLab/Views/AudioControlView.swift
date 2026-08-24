import SwiftUI
import UniformTypeIdentifiers

/// The audio cluster of the transport bar: file picker, transport buttons, current
/// position over the track length with a thin progress bar, live BPM, and manual/tap
/// tempo — one row, designed to sit between the show and sync clusters in
/// `TransportBarView`.
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

                HStack(spacing: 6) {
                    Button {
                        appState.audioEngine.restartFromBeginning()
                    } label: {
                        Image(systemName: "backward.end.fill")
                    }
                    .disabled(appState.audioEngine.trackURL == nil)
                    .help("Restart from the beginning")

                    Button(appState.audioEngine.isPlaying ? "Pause" : "Play") {
                        if appState.audioEngine.isPlaying {
                            appState.audioEngine.pause()
                        } else {
                            appState.audioEngine.play()
                        }
                    }
                    .disabled(appState.audioEngine.trackURL == nil)

                    Button {
                        appState.audioEngine.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .disabled(appState.audioEngine.trackURL == nil)
                    .help("Stop and reset to the beginning")

                    Button {
                        appState.toggleLooping()
                    } label: {
                        Image(systemName: "repeat")
                            .foregroundStyle(appState.audioEngine.isLooping ? Color.accentColor : Color.secondary)
                    }
                    .help(appState.audioEngine.isLooping ? "Looping — click to play once" : "Play once — click to loop")
                }

                // Fast-updating readouts live in their own observing leaf views so
                // their updates never re-measure this whole row — see LivePreviews.swift.
                LiveTrackTimeReadout()

                Divider().frame(height: 20)

                LiveBPMReadout()

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
                    Button("Tap") {
                        appState.tapTempo()
                    }
                    .buttonStyle(.borderless)
                    .help("Tap along with the music to set the tempo by feel")
                }

                Spacer(minLength: 0)
            }

            if let error = appState.audioLoadError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

#Preview {
    AudioControlView().environment(AppState())
}
