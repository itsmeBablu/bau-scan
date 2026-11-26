# LiDAR device checks — pending

## Design system S1–S4 — device validation pending

- After token migration, compare light/dark and increased contrast on iPhone/iPad
  and Mac; brand fills must retain readable labels, links/icons must stay legible.
- Test accessibility XXL Dynamic Type, VoiceOver names, 44-point targets and
  portrait/landscape safe areas. Capture controls must not alter session lifecycle.
- Confirm Reduce Motion changes feedback appropriately; recording state remains
  distinguishable without color. Compare exported plan/PDF/SVG/DXF content before
  and after theming; UI appearance must not change engineering deliverables.
- S0 is inventory only: none of these visual or physical checks has been run.

## UI redesign Phase 0 — device validation pending

- Open project details/settings and confirm no dead Scan more route is exposed.
- Edit one note in two windows/devices; save the newer edit, then the stale draft.
  Expect a visible conflict and retained draft, never a false success. Reload disk.
- Repeat for project notes, source deletion and local/iCloud source twins. A scan's
  cloud identity must not change the local project catalogue root.
- Verify text edits preserve audio playback, transcription and spatial positions.
- Equal export requests still create duplicates in Phase 0; artifact reuse belongs
  to Phase 5. Do not delete user exports during this validation.

No live LiDAR capture validation is claimed for this branch. Installing or
launching the app is not equivalent to validating these scenarios.

- [ ] Capture three adjacent House rooms with one shared ARSession; confirm room
  saves, RoomPlan restart, common coordinates, coaching and Finish behavior.
- [ ] Force-quit during every room/segment/media write and finalization; recover
  saved data, retry Finish, and confirm no completed package is overwritten.
- [ ] Large-room snapshot triggers: time, geometry growth, encoded-size growth,
  memory warning, pause, interruption and background flush expiry.
- [ ] Profile encoded bytes, snapshot milliseconds, resident memory, thermal state,
  peak finish memory, main-thread stalls and disk capacity; tune conservative limits.
- [ ] Resume via world-map relocalization behind a flag; failed alignment must
  prevent automatic merging of new rooms with recovered geometry.
- [ ] Technik new/changed/removed mesh anchors survive delta recovery without
  repeatedly serializing the full growing mesh; verify final package compaction.
- [ ] Photos and stopped voice clips survive force-quit immediately after capture;
  verify room, level, pose, orientation, timestamp and old-clip replacement safety.
- [ ] Record and release the mic while House and Technik cameras remain live;
  inspect audio category transitions, interruptions, meter/redraw rate and AR FPS.
- [ ] Verify pins target the intended surface/object in both scan types.
- [ ] Recover / Discard names the draft, preserves completed scans and unrelated
  drafts, and remains correct after interruptions at every storage crash point.
- [ ] Open existing roomscan, housescan and technicalroom packages, plus designs.

Local implementation is now present for the session store, capture checkpoints,
media persistence, technical deltas, partial recovery and gated alignment probe.
The first focused integration run passed 56 tests, including both localization
checks. See SCAN_PERSISTENCE_RESULTS.md for final validation totals.

The live microphone control uses a 180 ms hold threshold, 60-second maximum and
100 ms recorder meter interval. There is no live waveform over the camera. Inspect
`voice` logs alongside AR FPS before attributing a freeze to audio-session
changes. No physical camera fix or exact measurement accuracy is claimed.

A resumed stored Technik survey is captured as a separate draft revision so a
failed continuation cannot replace the original. Recovered House geometry is
partial; adding newly scanned rooms to its old coordinate system is not enabled.
The alignment experiment only displays tracking status and never authorizes a
merge. It must be followed by independently checking a known point.

## Voice/UI regression checks (new branch, all device checks unrun)

- [ ] Hold mic past 0.5 s in House and Technik; category/configuration notifications
  must not stop the recorder; inspect voice logs and Settings diagnostics.
- [ ] Disconnect an active microphone after the grace period; finish a partial clip
  with the input-loss reason. Output-only route changes must not stop recording.
- [ ] Test interruption began/ended, backgrounding, media reset and permission
  cancellation; delayed permission must never resurrect a stopped recording.
- [ ] Close during preparing, recording, busy writes and unstaged failure; confirm
  discard always exits and committed recovery copies remain.
- [ ] Check waveform, release-to-save and slide-left cancellation over live camera.
- [ ] Check project cards on small iPhones/iPad, five tabs, editable parties/defaults,
  ZIP opt-in privacy and the top-right Technik visibility menus.

### UI redesign — scan organization (device validation pending)

- Open a legacy project: scans show Unassigned until explicitly organized; no scan
  file is renamed or moved. Change organization, reopen, and inspect Studio/report
  names. Map a multi-storey house's detected stories without changing geometry.
- Start House and Technik independently through setup; cancel setup without camera
  access, then Start. Force quit after capture begins and recover the draft: project,
  floor/building/zone/number and stable identity must survive. Check iCloud/local.
- Duplicate a number in the same scope: verify alternative and Keep both preserve
  both scan packages. Move a scan to another project; verify labels remain.
- Test EN/DE, small iPhone, iPad, Mac organization editor, large text, dark mode,
  VoiceOver and save errors. These checks have not been run on this Windows host.
