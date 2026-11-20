# Technical Room Scanner — Next Tasks

This document is a handoff for continuing the dedicated Technical Room scanner on another device.

## Current direction

- Keep the House Scanner unchanged and isolated.
- Keep the Technical Room scanner on its own AR session and state model.
- Preserve the existing `TechnicalRoom` data model, provenance, SI units, and null accuracy values until device validation.
- Do not change `.roomscan` or `.housescan` formats without explicit approval.
- Do not claim DIN compliance or sub-centimetre accuracy.
- All LiDAR/AR functionality remains **device validation pending** until tested on an iPhone Pro.

## Next implementation order

### T2 implementation status — 20 November 2026

Branch: `codex/technical-room-t2-alignment`. Implementation and simulator verification do not establish device accuracy.

- Added a Codable in-memory journal retaining frame metadata, multiple raw-depth snapshots, multiple copied mesh snapshots, alignment events, and checkpoint evidence across interruptions.
- Retention is bounded: 3,600 frame records, 2,000 events, and approximately 64 MiB of copied snapshot payload. Dropped-record counts are visible; this is not a whole-process memory limit or disk persistence.
- Locked the reference frame after the first retained annotation. Invalid/non-finite corners are rejected. A third checkpoint must be independently measured and away from the origin–X baseline; observed coordinates, residual, tolerance, and acceptance are retained.
- Recovery securely unarchives the saved world map. Tracking recovery alone cannot unlock annotation: relocalisation and a new checkpoint are required. Unverified annotation overlays are hidden and unfinished pipe points are cleared.
- Added tracking, smoothed-FPS, resident-memory, low-light, and incomplete-depth warnings. The technical camera remains visible while its controls scroll; annotation sheets no longer tear down the native capture host.
- House scanning and `.roomscan`/`.housescan` formats were not modified. Technical evidence remains unsaved in memory until the independent T4 package is implemented.
- Automated verification: complete macOS scheme passed 173 tests; complete iOS simulator scheme passed 168 tests, both with zero failures. The final callback-isolation/stale-frame integration changes passed a focused iOS rerun of all 22 Technical Room tests.
- Physical iPhone validation is blocked: no iPhone was connected, and the user confirmed that it was unavailable. AR/depth/mesh and relocalisation remain **device validation pending**.

Changed files for T2:

- `RoomScanner/Domain/TechnicalRoom/TechnicalAlignmentSurvey.swift`
- `RoomScanner/Domain/TechnicalRoom/TechnicalCaptureJournal.swift`
- `RoomScanner/Domain/TechnicalRoom/TechnicalCaptureHealth.swift`
- `RoomScanner/Domain/TechnicalRoom/TechnicalCaptureState.swift`
- `RoomScanner/TechnicalRoom/Capture/TechnicalRoomScanCoordinator.swift`
- `RoomScanner/TechnicalRoom/Capture/TechnicalRoomFrameProcessor.swift`
- `RoomScanner/Scan/TechnicalRoomScanView.swift`
- `RoomScannerTests/TechnicalAlignmentSurveyTests.swift`
- `RoomScannerTests/TechnicalCaptureJournalTests.swift`
- `docs/TECHNICAL_ROOM_NEXT_TASKS.md`

#### Required physical T2 acceptance checklist

1. On an iPhone 14 Pro, start Technical Room capture and verify live camera frames, nonzero mesh patches, and raw-depth snapshots with calibration metadata. Capture several snapshots and verify earlier snapshots remain in the journal.
2. Set two floor corners, independently measure a third checkpoint away from their baseline, and compare the displayed residual. Check both accepted and rejected tolerances without claiming certified accuracy.
3. Add a pipe and equipment item, open/close their sheets, and verify the camera session continues. Confirm that changing the reference after annotations is rejected.
4. Save a recovery map, background the app or interrupt tracking, and verify overlays disappear and annotation tools lock. Restore the map; normal tracking alone must not unlock annotations. Recheck the physical checkpoint before continuing.
5. Confirm pending pipe points are cleared on alignment loss. Revisit lighting/depth gaps and review the capture-health warnings. Close the scanner and confirm the camera indicator turns off.
6. Record the device/OS, observations, residuals, failures, and any lost evidence. Do not mark T2 device-validated or populate `accuracyMm` until this has actually been performed.

### 1. Finish T2 capture and alignment

- Add a durable in-memory capture journal for frame metadata, depth snapshots, mesh snapshots, timestamps, tracking state, and alignment status.
- Prevent the room reference frame from being silently replaced after annotations exist.
- Add a third alignment checkpoint workflow with residual error and a visible “unverified” state when tracking/relocalisation fails.
- Save and restore an `ARWorldMap` for interruption recovery; require a successful alignment check before accepting new annotations.
- Add tracking-quality, FPS, memory, low-light, and incomplete-depth warnings.
- Keep all ARKit code under the iOS target; Mac must compile without ARKit/RoomPlan dependencies.

### 2. Finish T3 manual annotation foundation

T3 implementation on `codex/technical-room-t3-annotations` adds a separate `TechnicalAnnotationDocument`, transactional bounded undo/redo, manual rectangular duct routes, fittings and ports, endpoint-to-port connections and warnings, measurements and length-only calibration, raw-preserving control-point overrides, camera point dragging, snapping/axis locks, equipment/property editing, photos and notes. Domain code remains Foundation-only and Technical Room v1 interchange is unchanged. The complete macOS scheme passed 179 tests and the focused iOS annotation/schema run passed 12 tests. AR dragging, raycasts and placement remain device-validation-pending. Disk persistence is the next T4 milestone.

- Add manual duct routes with rectangular width/height and provenance.
- Add fittings (elbow, tee, reducer, flange, valve) and host relationships.
- Add equipment ports and pipe-to-port connections, including unconnected-end warnings.
- Add point-to-point measurement and manual scale calibration.
- Add edit/delete tools, drag control points, snapping, axis/90-degree locking, and undo/redo.
- Preserve raw surface hits and recompute derived centrelines when diameter or insulation changes.
- Add photos and notes without inventing measurements.

### 3. Independent persistence (T4)

- Create `Documents/TechnicalRooms/<UUID>.technicalroom/` without changing existing room/house packages.
- Store metadata, technical-room JSON, survey/alignment data, raw mesh/geometry references, annotations, measurements, photos, and thumbnail.
- Support save, reopen, edit, export, and schema migration tests for the technical package.
- Keep the platform-independent portion readable by `RoomScannerMac` without importing ARKit or RoomPlan.

### 4. Viewer and validation (T5–T6)

- Build a dedicated technical-room viewer: orbit, top/front/side views, semantic filters, selection highlighting, dimensions, elevations, and raw-vs-annotated toggle.
- Add a validation report: five pipe lengths, three equipment dimensions, three repeats, three alignment checkpoints, interruption/relocalisation repeat.
- Keep `accuracyMm` null until each measurement is actually validated.

### 5. Recognition and exports (T7–T8)

- Investigate Core ML/Vision only as a separate, confirmable recognition layer.
- Never treat furniture recognition as MEP recognition; never invent pipe routes or DN values.
- Add technical PDF, DXF, CSV schedules, unresolved-items report, and linked USDZ/raw mesh exports after the data and validation layers are stable.

## Required verification after each milestone

1. Run the iOS and macOS XcodeGen test schemes on a Mac.
2. Report files changed, tests added/passed, assumptions, and anything not verified on device.
3. Run a physical-device checklist on an iPhone 14 Pro before claiming AR/depth/mesh behaviour.
4. Keep one branch per phase and stop for review before starting the next phase.

## Continuation prompt

Copy and send this prompt on the other device:

> Continue the dWalkScan Technical Room Scanner work from `docs/TECHNICAL_ROOM_NEXT_TASKS.md`.
> First audit the current branch and git status; preserve all existing user changes and do not modify the House Scanner or `.roomscan`/`.housescan` formats. Work only on the next unfinished milestone, in small testable commits. Keep Domain code pure Foundation, keep ARKit/iOS code isolated from Mac, retain provenance on every value, and leave `accuracyMm` null unless validated. Before editing, list the exact files you will touch. After implementation, run both XcodeGen test schemes if a Mac is available, report what passed and what remains device-validation-pending, list changed files, and stop for review. Do not claim DIN compliance or engineering accuracy. If a required repository or Bau importer detail is missing, ask for it instead of guessing.

