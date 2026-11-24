# Scan photos and Studio selection

Branch: `codex/scan-photos-studio-selection`.

## Behaviour

- Settings includes **Camera photos during scanning** (initially enabled) and
  **Scan performance** (Quality / Balanced / Performance, initially Balanced).
- House and technical capture use a 52-point photo button at bottom right when
  camera tracking is normal. Successful capture gives light feedback and a short
  white flash; Reduce Motion uses a softer fade. No shutter sound is added.
- Every room starts its photo count at **1**. Revisiting a room continues that
  room's sequence. A technical-room package is one room and starts at 1.
- House photos are associated with final scanned room footprints at save time.
  For stacked footprints the current association uses camera elevation relative
  to the scanned floor. Photos outside every footprint are retained as
  **Unassigned room**, with an independent sequence. This association needs device
  validation, especially doorways, overlapping footprints and split-level rooms.
- Viewer and Studio photo markers show camera position, number and viewing
  direction. Photos opens a half-height gallery on iPhone, expandable with swipe,
  zoom controls, full-screen and **Go to camera**. Positions are scan coordinates,
  not GPS; **device validation pending**.
- **Open in Studio** uses the existing project's route from room, house and
  technical project detail controls, including their plan/view/measurement tabs.
- In either Studio, enable **Multiple selection**, tap editable objects, then
  **Delete selected**. Undo restores the entire deletion in one action. Original
  scan packages and architectural shell geometry are not deleted. Multi-object
  move/rotation is disabled; deletion applies to editable Studio objects.

## Source findings and changes

### Camera startup

`ScanCoordinator.start()` set `active` before checking permission, and previously
left it true on denied permission. A retry after changing Settings returned at
`guard !active`. Failure now clears that flag and foregrounding retries denied
House/Room capture. This is a verified source-level retry defect, not a claim that
every reported black screen has the same cause. Technical capture displays camera
errors and a Settings action even when its controls sheet is closed. Both capture
flows report missing frames after eight seconds. Existing House session ownership
and RoomPlan configuration are retained; photo capture reads its current ARFrame.
Radiator and AR viewer entry points already had permission/retry handling; no
additional competing session was introduced.

### Live mesh work

Technical preview copying and periodic per-vertex saved colour sampling previously
ran on the main actor. The preview rebuilt all mesh nodes for each snapshot.
Copying/colour sampling now use one bounded worker, previews skip colours, and
unchanged anchor nodes are retained. Live budgets are:

| Setting | Minimum update interval | Vertex cap | Triangle cap |
| --- | ---: | ---: | ---: |
| Quality | 0.5 s | 60,000 | 40,000 |
| Balanced | 1 s | 30,000 | 20,000 |
| Performance | 2 s | 12,000 | 8,000 |

Preview work skips if another worker is busy or sampled resident memory exceeds
800 MiB. FPS, anchors, preview vertices and worker milliseconds are displayed;
existing capture health includes memory. Saved mesh budgets, colour-sampling
algorithm, evidence encoding and package schema remain unchanged. Timing can
change under load: byte-identical capture output is not asserted. Final save waits
for in-flight work before freezing evidence. RealityKit mesh resource creation
still occurs on the main actor, with bounded changed patches only. AR mesh buffer
copying during live updates and worker lifetime need device stress testing.

**Before/after timings, peak memory and FPS are unmeasured on device.**

## Compatibility

Room/house core JSON files are unchanged. New photos use optional additive files
`survey-photos.json` and `survey-photos/<UUID>.jpg`, within the existing package.
Old packages without them remain valid; room rename/import/conflict duplication
preserves them, remapping the room reference on duplicated room imports.
Original camera matrices and frame timestamps are retained; optional display poses
apply the same alignment/floor normalization as the corresponding viewer.
House photos are limited to 200, 4 MiB per JPEG and 64 MiB total. Photo paths and
rigid transforms are validated. Technical capture reuses its existing keyframes;
`.technicalroom` and Technical Room v1 schemas are unchanged. No dependency added.
No accuracy values, standards compliance or engineering measurements are inferred
from photos.

## Tests and build status

Added tests in `SurveyPhotoTests.swift`: per-room numbering/revisit, Codable and
canonical paths, asymmetric pose conversion, settings gates/performance budgets,
legacy optional sidecar/read-write and invalid pose/path rejection.
`RoomPackageTests.swift` adds legacy package/photo round-trip and rename coverage.
`SceneStudioTests.swift` adds grouped deletion/undo/redo for both Studio sources.

This work was authored on Windows. XcodeGen, Swift and Xcode are unavailable here.
**Both Xcode test schemes are unrun. No Mac compilation or device test is claimed.**
On a Mac, run from the checkout (choose an installed iOS simulator if needed):

```sh
xcodegen generate
xcodebuild test -project RoomScanner.xcodeproj -scheme RoomScannerMac -destination 'platform=macOS'
xcodebuild test -project RoomScanner.xcodeproj -scheme RoomScanner -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

## iPhone/iPad manual checks — device validation pending

1. Deny camera access, enter each capture/AR entry point, verify visible error;
   enable camera in Settings and return. Check startup, rotation, background,
   interruption, recovery and that leaving releases the camera. Recheck ordinary
   House scanning and radiator detection.
2. Enable/disable photo setting. Check 52-point bottom-right placement on iPhone
   and iPad; take several photos, verify flash/haptic only after successful saves,
   Repeat with Reduce Motion. Check photo errors and budget exhaustion.
3. Scan rooms A and B, take A1, B1, A2, B2; save/reopen. Verify numbers, JPEGs,
   orientation and camera arrows. Test doorway/unassigned photos and aligned
   single-room scans against known visible corners. Reopen legacy packages.
4. Open normal house/technical viewers and Studio; toggle Photos, tap each marker,
   swipe gallery, zoom, full screen and Go to camera. Repeat Go to camera from 2D.
   Verify room names disambiguate repeated photo numbers and the correct project
   opens from each Open in Studio route.
5. In House and Technik Studio select two objects, deselect one, select all on
   the current floor, delete, undo and redo. Save/reopen the design. Confirm the
   original capture and architecture remain present and single-object editing works.
6. Run ten-minute technical scans in each performance setting; record FPS, worker
   milliseconds, memory, anchors and vertices periodically. Test final save during
   worker activity/photo encoding and after recovery, low light and thermal load.
   Compare saved mesh completeness/colours and evidence with the baseline build.

## Changed files

- Domain: `SurveyPhoto.swift` (new, Foundation only).
- Capture: `ScanCoordinator.swift`, `ScanView.swift`, `TechnicalRoomScanView.swift`,
  `HouseSurveyPhotoCapture.swift` (new); technical `TechnicalRoomScanCoordinator.swift`,
  `TechnicalRoomMeshCollector.swift`, `TechnicalRoomKeyframeCollector.swift`.
- Storage: `SurveyPhotoStore.swift` (new), `RoomPackage.swift`, `HousePackage.swift`,
  `RoomStore.swift`, `ConflictResolver.swift`.
- UI/viewers: `ScanPhotoButton.swift`, `SurveyPhotoGallery.swift`,
  `SurveyPhotoMarkers.swift` (new); `SettingsView.swift`, `ViewerView.swift`,
  `HouseDetailView.swift`, `RoomDetailView.swift`, `TechnicalRoomLibraryView.swift`,
  `TechnicalSavedScanView.swift`.
- Studio: `SceneEditDocument.swift`, `StudioEditorView.swift`, `StudioViewport.swift`.
- Tests: `SurveyPhotoTests.swift` (new), `RoomPackageTests.swift`, `SceneStudioTests.swift`.
- Documentation: this file.
