# Voice/UI regression audit

Requested baseline: `3f0e9a5` (2026-11-24). Actual starting HEAD: `f19789a`, not
`8d178dd`. Branch: `codex/voice-ui-regression-fix`. The baseline exists locally.
The requested path diff covers 25 files, +1584/-196 lines. No baseline recorder
exists: Notes/ was introduced after that revision. The alleged previous card UI
is not in baseline RenovationNavigation: it contains Home/Projects/Design/Search
lists and a permanent scan accessory. Restoring cards therefore requires new UI,
not blindly restoring that file.

## Behavior changes by affected component

- Notes/NoteAudioRecorder: new permission/session ownership, AAC capture, 60 s cap,
  metering, interruption handling and durable callback. BUG: every notification
  indiscriminately stops recording. Category-change/configuration notifications
  must not do so. Activation changes the audio route. Device reproduction is unrun.
- Notes/NotePlayback: new rate/scrubber/playback and session restoration. Intended;
  playback changes audio category and must not run concurrently with recording.
- Notes/ProjectVoiceNotesView: new linked scan list, recording/retry/export and
  recovery management. BUG: closure/back/dismiss guards can trap an unstaged clip;
  single-scan association is not auto-selected. Preserve storage, fix navigation.
- Scan/CapturePersistence, CaptureBackgroundFlush, RoomCheckpointObserver,
  ScanSaveStatus: new draft lifecycle, worker writes, live RoomPlan snapshots,
  memory/background flush and saved status. Intended requested persistence.
- Scan/ScanCoordinator: House now saves rooms on disk, uses Room done/Next room,
  builds the final structure from saved rooms; snapshot sampling, retry, resident
  memory/thermal counters and deferred native exports were added. Lifecycle change
  needs LiDAR validation. Retain completed persistence rather than reverting to
  memory-only final saving. Observer forwards coaching/final callbacks.
- Scan/ScanView: adds save status, partial/retry controls and compact live notes;
  package IO is on a worker. Preserves shared ARSession/radiator capture. Full-screen
  dependency injection was fixed after an actual iPhone missing-environment crash.
- Scan/HouseSurveyPhotoCapture: JPEGs saved immediately to draft media, metadata
  remains resident; assets loaded only for packaging. Intended.
- Scan/CaptureSurfacePoint: adds center-depth/raycast position. Intended annotation
  estimate, not accuracy-certified or semantic equipment identification.
- Scan/LiveScanNotes: new held microphone, surface text note and durable audio.
  Needs waveform/slide cancellation and camera-to-aim metadata; list sheets are
  already absent from the live House flow.
- Scan/ScanRelocalizationProbe: new read-only, disabled-by-default experiment. Never
  merges recovered/new rooms. Preserve safety guard; device checks remain unrun.
- Scan/TechnicalRoomScanView: adds live notes/checkpoints, separate revision IDs,
  background deltas and final compaction; view retains independent technical camera.
- TechnicalRoom/Capture/TechnicalRoomScanCoordinator: stores changed anchor/journal
  deltas, world-map candidates and immediate media. Uses existing tracking and
  reference/checkpoint restrictions. Worker/flush timing needs device validation.
- TechnicalRoom/Capture/TechnicalRoomKeyframeCollector: additive capture timestamp.
- UI/Projects/RenovationNavigation: root now project list; each project has three
  working tabs. Removed duplicate room capture choice. Item destinations reload
  their store. Scan wrapper injects dependencies explicitly. Intended fixes; five
  requested tabs/cards/details remain to implement.
- UI/Projects/RenovationWorkspace: exposes notesRoot; no capture lifecycle change.
- UI/Projects/ProjectPinsView: uses returned persisted SceneEditStore document;
  intended lost-revision fix, not camera behavior.
- UI/Projects/UnfinishedScansView: new Recover/Discard/retry entry; intended.
- UI/HouseDetailView: adds photos, notes, partial label, keyboard navigation, and
  source-photo viewer linkage. Intended, but full notes list remains management UI.
- Viewer/PlanSceneBuilder: adds camera/photo markers and selection collisions;
  intended, preserve coordinate transforms and bounds guards.
- Viewer/ViewerControls: groups options, adds notes entry, restricts virtual ruler
  in AR. Intended decluttering; notes management should not block live capture.
- Viewer/ViewerMode: adds virtual measurement state. No camera lifecycle change.
- Viewer/ViewerView: adds virtual measurement gestures, photo gallery/marker flight,
  split RealityView gestures and an iOS-compatible unproject API. Camera-backed
  ARView remains independently owned. Do not revert the API fix or resurrect the
  compile-time location3D failure. Photo visibility remains separately controlled.

## Fix policy and evidence

Restore non-stopping audio behavior for self-induced route changes; add a pure
policy, bounded preparation and diagnostics. Keep playAndRecord only when the
current category cannot record; do not rerun RoomPlan/ARKit to repair audio.
Add an always-available confirmed close/discard path to notes management.
No physical microphone/camera freeze cause is proven by compilation or simulator
logic tests. The audio event policy is checked against Apple's documented route
reasons: https://developer.apple.com/documentation/avfaudio/avaudiosession/routechangereason

The supplied instruction requires stopping if a step exceeds about 300 lines.
Changes will be measured per step; no unreviewed large redesign will be slipped
into the audio fix. Physical-device checks remain in DEVICE_TEST_CHECKLIST.md.
