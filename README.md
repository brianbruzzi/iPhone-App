# FaderLab

A macOS app that automates a Behringer X-Touch's motorized faders (wave motion or
beat-synced pulses) and turns a Novation Launchpad X's 64 RGB pads into an animated
pixel-art display — both driven off the same shared beat clock so the two stay in sync
with each other and with music played from within the app.

## Try it — no Xcode, no hardware required

Every push to this project automatically builds a ready-to-run copy of the app. You do
**not** need Xcode installed, and you do **not** need the X-Touch or Launchpad plugged in
to try it out — the app shows an on-screen preview of exactly what the fader positions and
Launchpad colors would be, right in the window.

1. Go to the **[Actions tab](../../actions/workflows/build.yml)** of this repository.
2. Click the most recent run with a green checkmark ✅.
3. Scroll down to **Artifacts** and click **FaderLab-app** to download a `.zip` file.
4. Unzip it (double-click the `.zip` in Finder) — you'll get `FaderLab.app`.
5. **First time only:** don't just double-click it. Right-click (or Control-click)
   `FaderLab.app` and choose **Open**, then click **Open** again in the dialog that pops
   up. This is a one-time step macOS requires for apps not downloaded from the App Store —
   after this, it opens normally.
6. Try the app: pick a fader pattern and a pixel-art pattern from the dropdowns, drag the
   sliders, and load a song to watch the beat detection kick in — watch the bars and the
   little colored grid animate live in the window.

If a run shows a red ❌ instead of a green checkmark, that means the automatic build hit a
problem — no need to debug it yourself, just flag it and it'll get fixed.

## Hardware

- **Behringer X-Touch** (full-size, 9 motorized 100mm faders — not the Compact/Mini
  variants, which don't have motorized faders).
- **Novation Launchpad X** (8x8 RGB pad grid).
- Both connected to the Mac via USB (class-compliant, no drivers needed).

## One-time hardware setup

### X-Touch: switch it into MC (Mackie Control) mode

The X-Touch must be in **MC mode** for the fader-automation protocol in this app to work.
This is a physical setting on the unit itself — the app cannot do this for you. Consult
your X-Touch's Owner's Manual "Setup"/"MIDI" section to confirm the exact key combination
for your firmware revision (it varies across hardware/firmware revisions), typically
reached by holding a Function/channel-select key while powering on to reach a mode-select
screen, then choosing "MC".

### Launchpad X: two USB MIDI ports — use the right one

The Launchpad X exposes **two** USB MIDI port pairs: `LPX DAW` (Ableton session control —
not used by this app) and `LPX MIDI` (Programmer Mode note/SysEx lighting — what this app
needs). The app's auto-discovery specifically looks for `LPX MIDI` and excludes `DAW`; if
for some reason it picks the wrong one, use the "Manually select MIDI ports" disclosure in
the app's Devices panel to choose the `LPX MIDI` in/out pair explicitly.

## Building

Open `FaderLab.xcodeproj` in Xcode 16 or later. The `FaderLabCore` local Swift Package
dependency should resolve automatically. Build and run the `FaderLab` scheme (macOS 14+).

**If the project doesn't open cleanly** (e.g. an older Xcode version that doesn't
understand the modern file-system-synchronized project format used here): create a new
blank macOS App (SwiftUI) project, drag the `FaderLab/` folder's contents into it as
group references, then add `FaderLabCore` as a local Swift Package dependency via
*File > Add Package Dependencies… > Add Local…*, pointing at the `FaderLabCore/` folder.

### Running the core package's tests

`FaderLabCore` has zero Apple-only framework dependencies beyond `Accelerate` (pure math,
no CoreMIDI/AVFoundation/SwiftUI), so its test suite can run standalone:

```
cd FaderLabCore
swift test
```

This covers the X-Touch and Launchpad X byte-level protocol encoders against their
specs, all fader/pad pattern generators, the onset detector, and the beat clock —
everything except the CoreMIDI/AVFoundation glue and the SwiftUI views, which need a real
Xcode build (and, for anything hardware-facing, the actual devices plugged in) to verify.

## Architecture

- **`FaderLabCore`** (Swift Package) — pure Swift + Accelerate/vDSP, no CoreMIDI/
  AVFoundation/SwiftUI. All protocol byte-encoding, pattern generation, and beat/onset
  detection logic lives here, which is what keeps it unit-testable without any hardware.
  - `XTouchProtocol` — Mackie Control pitch-bend fader positions + touch-sense decoding.
  - `LaunchpadXProtocol` — Programmer Mode SysEx: RGB frames, mode toggle, grid<->note mapping.
  - `FaderPattern` / `PadPattern` — the animation generators (see below).
  - `SpectralFluxOnsetDetector` / `BeatClock` — local beat detection and a shared,
    predictive beat-phase clock.
  - `PatternEngine` — hardware-agnostic orchestrator; ticks patterns and emits frames via
    closures, tracks which faders the user is currently touching so automation doesn't
    fight their hand.
- **`FaderLab`** (Xcode app target) — thin platform glue only: `MIDIManager` (CoreMIDI
  device discovery/I-O), `AudioEngine` (AVAudioEngine playback + tap -> onset detector),
  `AppState` (composition root + ~30Hz tick timer), and the SwiftUI views.

## Patterns

**Faders:** Wave (sine sweep across the bank), Beat Pulse (unison jump-and-decay on each
beat), Beat Chase (one fader lit at a time, advancing per beat), Off (releases faders to
manual/DAW control).

**Launchpad:** Plasma Wave (demoscene-style sine-field plasma), Rainbow Chase (diagonal
hue sweep), Beat Ripple (expanding ring from center on each beat), VU Columns (8 columns
as a live audio-level meter, green->yellow->red).

## Known limitations

- **Beat detection is onset-reactive, not full beat-induction.** Spectral-flux onset
  detection reliably catches percussive transients (drum hits, note attacks), which is
  what the flash/pulse-style patterns need — but it doesn't solve "which transient is
  *the beat*" the way a trained ML beat tracker would. The BPM estimate (inter-onset-
  interval histogram with octave-error folding) is a reasonable approximation that works
  well on typical percussive music (EDM/rock/pop) and can drift on sparse or syncopated
  material.
- **Cleanup on quit is best-effort.** The app tries to turn off the Launchpad's pads and
  switch it back to Live mode when it quits, but SwiftUI doesn't guarantee a termination
  callback fires on every quit path (e.g. a force-quit). If the Launchpad is ever left in
  Programmer Mode with stale colors, just relaunch the app — it re-sends the reset on the
  next successful quit, or you can power-cycle the Launchpad.
- **App Sandbox is off.** This is a personal tool, not intended for Mac App Store
  distribution, so sandboxing was skipped to avoid any CoreMIDI/USB entitlement edge
  cases rather than because it was verified to be necessary.
- This app was written in a sandbox with no Xcode/Swift toolchain at all, so it couldn't
  be built there directly — but GitHub Actions' macOS runners now build it on every push
  (see "Try it" above), which confirmed the app compiles cleanly. What still hasn't been
  verified is anything that needs the *physical* X-Touch/Launchpad plugged in (motor feel,
  actual color/latency on the Launchpad) — that only you can check.
