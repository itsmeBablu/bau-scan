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

### Project navigation/dashboard (device validation pending)

- Launch into Projects: no tab bar. Toggle list/grid, search and sort; relaunch and
  confirm preferences. Rename a project. Open its deletion route and cancel at
  confirmation; no file should change. Verify Unsorted and recovery stay accessible.
- Open a project: five tabs; each preserves its own navigation and returns to the
  correct project. Projects back action returns to the picker. Check iPad sidebar,
  compact iPhone, rotation, VoiceOver and large text for duplicate bars/clipping.
- Dashboard shows existing plan thumbnails; no export is created on appearance.
  Compare union area within each scan and sums across separate scans; Studio copies
  do not increase totals. Change a plan, refresh and verify summary invalidation.
  Disconnect a library and confirm unavailable data isn't presented as current.
- Edit details through the sheet; open written notes and reproduce stale-editor
  conflicts across windows. Actual Apple rendering/build validation remains unrun.

- Grouped libraries (device validation pending): collapse/reopen building and floor
  groups; verify UG 2, EG, 2. OG precede 10. OG numerically. Legacy scans stay under
  Unassigned, named floors stay named. Switch list/grid and tabs; inspect large text
  and narrow iPhone disclosure controls. House room labels reflect explicit story
  mappings; mapping never changes scan coordinates or raw story indices.

- Capture controls (device validation pending): check Close/name/Finish on iPhone
  portrait/landscape and iPad; microphone/pin left, shutter right, no overlap at
  large text. Open Technik tools/display menu and return to camera. Verify hold,
  slide-cancel, VoiceOver tap start/stop, photo capture, warnings, retry and Finish.
  Confirm tracking/session continuity is unchanged by opening tools or display menus.

- Inline voice (device validation pending): play/pause/seek several clips; starting
  another must stop the first, including another open note player. Verify real
  waveforms after loading, text size/VoiceOver and elapsed/total. Test an unavailable
  or replaced clip, recording after playback, audio route interruptions, leaving
  the screen and memory during repeated playback. No playback test ran on Windows.

- Lazy photo library (device validation pending): browse a large mixed House/Technik
  project while watching memory; scroll away/back, search/filter by scan, open and
  swipe through images, zoom, full screen, share/Save to Files. Confirm numbers and
  raw camera poses are unchanged and Studio copies add no duplicates. Test missing,
  corrupt and iCloud-placeholder assets; failures must be visible without crashing.

- Recent dashboard evidence (device validation pending): add/rename a note or photo,
  switch away/back and refresh; preview counts/order must update. Play two clips in
  rapid succession while the first loads, then navigate or start recording; old
  results must not begin playback. Confirm only the selected clip is loaded and
  leaving a row/screen stops its player. Verify no export appears on dashboard entry.

- Photo hierarchy (device validation pending): filter mixed building/floor/zone/room
  collections, including Unassigned and duplicate room names. Changing a parent
  clears child filters. Basement/upper floors sort numerically; multi-storey photos
  require explicit story mappings. Export one project from a multi-project catalogue
  and verify project-index.json validates and contains only that project's metadata.

- Selected photo ZIP (device validation pending): select across several filters,
  clear/select-visible, export, Share/Save to Files and unzip. Verify only selected
  images, building/floor/room folders, Bath Room 2 collisions, original numbers and
  camera metadata. Cancel by navigating away; stale results must not replace a new
  export. Test missing/iCloud photos, over-limit selections and low disk space.
  Validate manifest checksums and confirm original scan files are unchanged.

- Export intent/library (device validation pending): open and change formats/mesh
  source without Generate; no file should be created. Generate, dismiss/cancel and
  reopen; old results must not appear. Verify Photos ZIP stays selected independently
  of mesh options. Browse categories, preview supported types, Share/Save to Files,
  rename (including collision) and cancel/confirm deletion. Check only the exported
  file changes; source scans and other exports remain. Test small iPhone footer,
  iPad/Mac Quick Look, large text, unavailable files and no network/iCloud.

- Studio/details polish (device validation pending): use Select/Add/Move/Rotate/Edit/
  More, Undo/Redo and Save in portrait/landscape/large text; verify state/geometry
  matches existing behavior. Mac shows one inspector. Edit project fields, visit
  App settings and return; draft must remain. Open two editors, save one, then save
  the stale one; conflict stays visible and draft remains. Test reload/discard,
  save-and-close, swipe dismissal, invalid fields and a project deleted elsewhere.

- Preference isolation (device validation pending): configure two projects with
  different language, units, export format and photo defaults. Open/start/close each;
  app defaults must remain unchanged. Check measurement viewers, 2D labels, export
  selection/units, photo toggles and note language metadata. Save a local House from
  a cloud browsing library and verify project reference/library identity; browsing
  location stays unchanged. Request disconnected iCloud and verify setup explains
  the connection requirement without enabling it. Technical capture remains local.
  Test force-root fixtures, recovery, rotation and returning to global App Settings.

- Project artifact reuse (device validation pending): Generate CSV/PDF twice with no
  changes; second request must reuse the exact file. Edit geometry, notes, language,
  units/options or a source photo; create a distinct labelled revision. Rename an
  indexed file and reuse it. Modify/delete that file externally; regeneration must
  preserve modified bytes and create/recover an artifact. Exercise concurrent windows,
  cancellation, unavailable sources, iCloud sync and low disk/index-write failure.
  Legacy UUID files must remain; inspect .artifact-index-v1.json and SHA-256 records.

- Real names/deduplication (device validation pending): export a named floor plan and
  verify its actual name in the filename. Repeat with identical content under a
  different label: same saved file/path, no second copy. Change content: retain old
  file and add numbered version. Repeat in room/house Save to exports and iCloud.
  Check Unicode/long/unsafe names and indexed rename/delete shared by two requests.

- Notes workflow (device validation pending): create/search/edit a project/scan/room
  text note, reopen and verify persistence. Delete written text from a combined note;
  audio/transcript must remain. Try stale editors across windows. In voice rows test
  contextual rename/re-record/share/delete; deny microphone, fill disk, interrupt
  recording and retry save. Old audio must remain until replacement commits. Close
  dirty text without losing it; cancel/stop/retry before dismissal. Check VoiceOver,
  large text and Mac text-only editing. Recovery copies remain available after errors.

- Shared photo hierarchy (device validation pending): compare selected, all-photo,
  complete-project and single-scan ZIPs. Each contains building/floor/room photo
  folders with correct original numbers, same-room grouping and Bath Room 2 naming.
  Verify explicit story mappings versus Unassigned and camera metadata sidecars.

- Final marker/plan visuals (device validation pending): inspect 3D, Studio, Technik
  saved viewer and 2D in System/Light/Dark/high-contrast. Camera/waveform icons must
  have no filled background disk, remain legible and tappable, and show the selected
  photo below/highlight its icon. Verify slightly larger direction guides follow
  the original camera pose; vertical cameras have no misleading 2D wedge. Compare
  paper plan linework/dimensions/grid at zoom and large text with approved concepts.
  Test toolbar scrolling, photo/audio selection, orbit/drag and narrow/landscape iPhone,
  iPad and Mac. These are manual checks; no actual app screenshots were captured here.

- Library actions (device validation pending): Export/measurement report from both
  House and Technik cards; opening must create no file, Generate uses the actual
  scan name. Cancel/close while loading. Remove an item only after confirmation:
  dependent Studio source is blocked, unrelated items/notes/exports stay intact,
  and hidden sibling trash retains the removed bytes. Exercise concurrent edits,
  offline libraries, symlinks, failed catalogue commit and cancellation/rollback.

### Required Apple validation before calling this redesign finished

On a Mac at the exact local branch commit: run `xcodegen generate`, then
`bash Scripts/test.sh all`. Preserve the full xcodebuild log for any failure and
return its first compiler error plus context. Run iPhone 14 Pro capture, photos,
voice replacement/recovery and background tests above; inspect iPad/Mac adaptation,
light/dark/high contrast/Dynamic Type, navigation/dirty-close and screenshot parity.
No Apple builds/tests or actual app screenshots were produced on Windows.
