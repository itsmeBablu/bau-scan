# Camera, voice and AR pin fixes — 2026-11-26

## Changes

- Replaced competing SwiftUI microphone gestures with a fixed 48-point UIKit touch control. The waveform and feedback use overlays and do not move the held control. Slide left cancels; release saves a valid clip.
- Place a spatial pin first without opening a sheet. Tap the projected AR marker to select it for inline text or voice; tap again to deselect. Recording captures its association at start.
- Commit voice evidence to the local outbox/project sidecar before mirroring it into the scan checkpoint. A checkpoint cannot hold the microphone save UI busy. Revisions preserve newer audio and text independently, and text edits retain audio.
- Recover notes before promoting room geometry. A draft with missing geometry remains recoverable evidence and shows a specific message; no room geometry is invented.
- Fixed a reproduced infinite session-store path-validation loop caused by `/var` versus `/private/var`. Canonical containment, symlink rejection and a bounded parent walk replace literal-root termination.
- Removed manual Room done/Next room controls, the normal save-status badge, the House scan badge and the radiator candidate caption from House capture. Partial checkpoints continue in the background; Finish ends the continuous capture.
- Keep the display awake while either capture view is active; restore the previous idle policy on exit/inactivity. This does not override OS thermal dimming.
- Small camera, microphone and pin markers in saved 3D/Studio views; selecting notes opens text editing/recording/playback. Marker visibility updates avoid rebuilding House geometry. Visible markers are capped while full notes remain stored.
- Removed duplicate legacy wall-corner patches from exported meshes, fixed canonical relative paths in native snapshots, bundled the missing technical handoff schema, and corrected desktop-computer classification priority.

## Verification

- Full iOS simulator suite: **414 tests passed**, zero failures.
- Full macOS suite: **415 tests passed**, zero failures.
- Python service: **13 tests passed**, one existing Starlette/httpx deprecation warning; requirements installed only in a temporary virtual environment.
- JSON helper: **3 tests passed**.
- Localization audit: **1,220 keys**, no missing German translations or unextracted literals.
- Whitespace check passed.
- iOS test log: `/tmp/dwalk-camera-ios-all-tests.log`; Mac test log: `/tmp/dwalk-camera-mac-all-tests4.log`.

## Device validation pending

Install/launch status is recorded after the signed build. Compilation, unit tests and launching the app do not verify a held microphone gesture, world-locked AR interaction, long-session memory or recovery after a real process interruption. Check those on the iPhone before treating the architecture plan's device gate as complete. No remote CI run or performance improvement is claimed here.

The final WhatsApp-style one-row voice control is separately queued after architecture phases 0–10.
