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

## Physical follow-up

The user reported that House capture still froze/shook and showed scan failure when recording after the first installation. Technik recording was then confirmed working. The architecture/device gate is therefore **not passed**.

The next iteration configures a recording-capable audio route before RoomPlan starts, borrows that route while recording (no mid-capture activation/deactivation), and defers native House camera construction until the retained view resource is first used. A signed iPhone build, nine focused lifetime/recorder/recovery tests and the full 416-test iOS simulator suite passed. That iteration is installed for retesting; its physical result is pending. Full-suite numbers above describe the preceding commit, not this follow-up iteration.

## Linked marker update

- Notes use the local project catalogue even for iCloud scan packages. Legacy direct-capture notes in Unsorted remain discoverable; local/cloud twins stay distinct.
- 2D, virtual 3D, saved AR and Studio show note icons. Icons have explicit tap volumes and remain visible as annotations over model surfaces.
- Photo camera-direction frustums are restored in House/Studio. These legacy photo guides are illustrative, not calibrated viewing-volume measurements.
- Pins retain the capture camera position, with leaders to the observed mesh/wall point. Voice clips float above their anchor. Explicit selection takes priority; otherwise a text pin within 0.35 m can be associated. Clips have separate IDs and do not replace previous recordings.
- Full Mac suite: 423 passed. Final iOS result is recorded below when complete.
- Signed build passed; the updated Test app installed and launched successfully on the iPhone. Physical verification of the final marker appearance remains pending; launch is not an AR interaction test.
- Architecture phases 0–10 and the final WhatsApp-style voice row/name/context-menu additions remain queued, not implemented in this update.
