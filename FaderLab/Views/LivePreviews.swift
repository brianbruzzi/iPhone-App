import SwiftUI
import FaderLabCore

/// Tiny observing wrappers around the three hardware previews and the transport readouts.
///
/// With @Observable, the invalidation unit is *the view whose body read the property* —
/// so if a card's own body reads `latestFaderValues`, every 20Hz preview publish
/// re-evaluates the whole card and re-measures its AppKit-bridged controls (pickers,
/// text fields, sliders), which is where the real layout cost lives. These wrappers exist
/// so that the ONLY views reading the fast-changing properties are single-Canvas leaves:
/// a preview repaint re-draws one Canvas and touches nothing else. This is half of the
/// fix for the Round 7 fader-motor buzz (the other half is the UI-publish throttle in
/// AppState.tick) — keep it this way: never read `latestFaderValues`, `latestPadGrid`,
/// `latestSurfaceFrame`, or `elapsedSeconds` from a container view's body.
struct LiveFaderBars: View {
    @Environment(AppState.self) private var appState
    var barHeight: CGFloat = 140

    var body: some View {
        FaderBarsPreviewView(values: appState.latestFaderValues, barHeight: barHeight)
    }
}

struct LiveSurfacePreview: View {
    @Environment(AppState.self) private var appState
    var scale: CGFloat = 1

    var body: some View {
        SurfacePreviewView(frame: appState.latestSurfaceFrame, scale: scale)
    }
}

struct LivePixelGrid: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        PixelGridPreviewView(grid: appState.latestPadGrid)
    }
}

/// The "1:23 / 3:45" readout plus the thin progress capsule. Isolated for the same
/// reason: `elapsedSeconds` updates at the preview rate, and reading it from
/// AudioControlView's own body would re-measure the whole transport row each time.
struct LiveTrackTimeReadout: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(formattedTime(appState.audioEngine.elapsedSeconds)) / \(formattedTime(appState.audioEngine.trackDuration))")
                .monospacedDigit()
                .font(.callout)
                .foregroundStyle(.secondary)
            Capsule().fill(Color.white.opacity(0.10))
                .frame(width: 170, height: 3)
                .overlay(alignment: .leading) {
                    Capsule().fill(Color.accentColor)
                        .frame(width: 170 * progressFraction, height: 3)
                }
        }
    }

    private var progressFraction: CGFloat {
        let duration = appState.audioEngine.trackDuration
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(appState.audioEngine.elapsedSeconds / duration, 0), 1))
    }

    private func formattedTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Live BPM + beat-clock state, isolated because `currentBPM`/`currentAudioLevel` update
/// from the audio tap many times a second while a track plays.
struct LiveBPMReadout: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(Int(appState.audioEngine.currentBPM.rounded())) BPM")
                .monospacedDigit()
            Text(isBeatLive ? "Live" : "Free-running")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var isBeatLive: Bool {
        appState.audioEngine.beatClock.snapshot(now: appState.audioEngine.currentHostTimeSeconds()).isLive
    }
}
