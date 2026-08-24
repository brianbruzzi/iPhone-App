# FaderLab

A macOS app that automates a Behringer X-Touch's motorized faders (wave motion or
beat-synced pulses) and turns a Novation Launchpad X's 64 RGB pads into an animated
pixel-art display — both driven off the same shared beat clock so the two stay in sync
with each other and with music played from within the app.

## Try it — no Xcode, no hardware required

Every push to this project automatically rebuilds the app. You do **not** need Xcode
installed, and you do **not** need the X-Touch or Launchpad plugged in to try it out — the
app shows an on-screen preview of exactly what the fader positions and Launchpad colors
would be, right in the window.

### Install (recommended — no Gatekeeper popup)

Open **Terminal** (press `Cmd+Space`, type "Terminal", hit Enter), paste this line, and
press Enter:

```bash
curl -fsSL https://raw.githubusercontent.com/brianbruzzi/iPhone-App/claude/faders-launchpad-midi-automation-u4z9u7/install.sh | bash
```

That downloads the newest build, installs it to `~/Applications`, and opens it. **Run the
same line any time you want to update** — or just double-click the
`Update FaderLab.command` file it drops next to the app, and skip Terminal entirely.

**Why Terminal instead of just downloading the zip?** macOS tags files downloaded *by a
browser* with a "quarantine" flag, and it's that flag — not the app — that triggers the
"unidentified developer" block and sends you to System Settings. `curl` doesn't set the
flag, so Gatekeeper never gets involved in the first place. (Note: the old
"right-click → Open" trick you may have read about **no longer works** — Apple removed it
in macOS 15 Sequoia.)

*Security tradeoff, stated plainly:* this skips Apple's signature check **for this one
app**, substituting "Apple vouched for this binary" with "I trust my own repo and my own
CI." Nothing else on your Mac is affected. Do not do this for software you didn't build
yourself.

### Manual download (if you'd rather not use Terminal)

**[Download FaderLab.zip](../../releases/download/latest-build/FaderLab.zip)** — this link
always points at the newest build. After unzipping, macOS will block it; you'll need to
either run this in Terminal once per download:

```bash
xattr -dr com.apple.quarantine ~/Downloads/FaderLab.app
```

...or go to **System Settings → Privacy & Security**, scroll down, and click **Open
Anyway**. The installer script above exists specifically to avoid this dance.

### Installing on another Mac (no internet — e.g. on set)

The app is fully self-contained and never needs internet to run: audio comes from local
files, MIDI from the connected hardware. Requirements: **macOS 14 or newer**, Apple
Silicon or Intel (the build is universal).

1. On any Mac that *is* online, **[download FaderLab.zip](../../releases/download/latest-build/FaderLab.zip)**
   and copy it to a USB stick.
2. On the target Mac: copy the zip over, double-click it to unzip. The folder contains
   `FaderLab.app` and `Install FaderLab.command`.
3. Double-click **`Install FaderLab.command`**. It copies the app to `~/Applications`,
   clears the Gatekeeper quarantine flag, and launches it. Done.

If macOS refuses to open the `.command` file itself ("unidentified developer"), open
Terminal and run it through `bash`, which sidesteps that check:

```bash
bash ~/Downloads/"Install FaderLab.command"
```

(Adjust the path to wherever you unzipped. Running a script through `bash` executes it
without the double-click Gatekeeper check — same trust tradeoff as the curl installer
above.)

### Then

Pick a fader pattern and a pixel-art pattern from the dropdowns, drag the sliders, and load
a song to watch the beat detection kick in — the bars and the little colored grid animate
live in the window, hardware or not.

If the download link 404s, the build hasn't finished yet — check the
**[Actions tab](../../actions/workflows/build.yml)** for a green checkmark and try again.

## Hardware

- **Behringer X-Touch** (full-size, 9 motorized 100mm faders — not the Compact/Mini
  variants, which don't have motorized faders).
- **Novation Launchpad X** (8x8 RGB pad grid).
- Both connected to the Mac via USB (class-compliant, no drivers needed).

## One-time hardware setup

### X-Touch: switch it into MC (Mackie Control) mode — REQUIRED

**The X-Touch ships in HUI mode, not MC mode.** In HUI mode it ignores the messages this
app sends entirely, so faders won't move and nothing lights up — even though the app will
happily report the device as connected. This is the single most common reason FaderLab
appears to do nothing.

This is a physical setting on the unit; the app cannot change it for you:

1. Power the X-Touch **off**.
2. Hold down the **channel 1 SELECT** button.
3. Keeping it held, switch the rear **power on**, and keep holding for ~2 seconds.
4. The scribble strips (the little displays above the faders) become a settings menu.
   - Turn **encoder 1** until it reads **`MC`**
   - Turn **encoder 2** until it reads **`USB`**
5. Press **channel 1 SELECT** again to save and boot into MC mode.

Two easy mistakes:
- If **encoder 2** is set to `MIDI` or `Network` instead of `USB`, nothing reaches the app
  over USB no matter what mode you picked.
- Instructions telling you to "hold the **MC** button while powering on" are for the
  *X-Touch Compact / Mini*. The full-size X-Touch has no MC button — use the procedure
  above.

You can confirm the mode worked from inside FaderLab: open the **Diagnostics** panel, touch
a fader with your hand, and check the detected mode. It'll tell you outright whether the
surface is talking MC, Ctrl, or HUI.

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
beat), Beat Chase (one fader lit at a time, advancing per beat), Sweep (Knight-Rider-style
scanning comet), Random Jitter (each fader wanders independently), Off (releases faders to
manual/DAW control).

**Launchpad:** Plasma Wave (demoscene-style sine-field plasma), Rainbow Chase (diagonal
hue sweep), Beat Ripple (expanding ring from center on each beat), VU Columns (8 columns
as a live audio-level meter, green->yellow->red), Sparkle (twinkling stars), Bouncing Ball
(DVD-screensaver-style bounce).

Every slider has a small tick mark showing its default value and a reset icon that
appears when it's been changed; each panel also has its own "Reset" button, and there's a
"Reset Everything to Defaults" button at the bottom of the window.

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
