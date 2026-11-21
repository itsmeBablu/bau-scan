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

T4 implementation on `codex/technical-room-t4-persistence` creates a separate local library under `Documents/TechnicalRooms/<UUID>.technicalroom/`. It supports capture save with a rendered thumbnail, library reopen and manual property edits on iOS/Mac, photos/notes viewing, package import/export, recoverable deletion, and iOS AR resumption from a securely restored map. Reopened AR capture never trusts an old checkpoint: relocalisation and a new physical checkpoint are required. Save freezes capture evidence and releases the camera before writing; failed saves retain the frozen in-memory survey for retry.

The first independent package format is version 1. There is no earlier `.technicalroom` format to migrate. Unknown versions are rejected without rewriting the source; migrations must be added explicitly when a real successor format exists. The room/house formats and House Scanner remain unchanged.

Package contents:

- `manifest.json`: identity, name, creation/modification dates, format version, checkpoint-at-save flag, and `deviceValidationPending` status. Dates use Foundation Codable's seconds-since-2001 representation.
- `technical-room.json`: unchanged Technical Room v1 interchange, including canonical raw observations and their provenance.
- `annotations.json`: annotation document with ducts, port connections, measurements, length calibration and point overrides. It omits photo bytes. Consumers use `effectiveRoom`/effective duct points for adjusted geometry; original raw surface hits remain available. Length correction does not rescale the AR geometry.
- `survey.json`: reference corners/frame, reference lock, checkpoint observations, residuals and tolerances.
- `capture.json`: bounded frame/depth/mesh journal and events. AR frame timestamps remain session-local; snapshot eviction uses capture order, including across restored sessions.
- `world-map.archive`: optional secure ARWorldMap archive; Mac preserves these opaque bytes without importing ARKit.
- `thumbnail.png` and `photos/<UUID>.jpg`: optional rendered thumbnail and user-selected JPEG survey-photo copies.

Storage is coordinated and staged. A failed replacement restores the old package; an interrupted replacement backup is recovered on library reload if the canonical item is missing. Uncommitted staging directories are not promoted automatically. File-size limits, SI units, canonical asset paths, symlink boundaries, reference evidence and journal structure are validated. Invalid/unsupported library items are reported without preventing healthy surveys from loading. Recoverable deletion moves one item into the library's private `.Trash` folder.

Final T2–T4 automated verification: **190 macOS tests and 185 iOS simulator tests passed**, with zero failures. A final focused macOS package run passed all nine tests, including opening an already-owned package without creating a duplicate. AR hardware acceptance is still pending; no engineering accuracy or DIN-compliance claim is made.

T4 file inventory:

- `RoomScanner/Storage/TechnicalRoomPackage.swift`
- `RoomScanner/Storage/TechnicalRoomLibraryStore.swift`
- `RoomScanner/TechnicalRoom/TechnicalRoomLibraryView.swift`
- `RoomScanner/TechnicalRoom/Capture/TechnicalRoomScanCoordinator.swift`
- `RoomScanner/TechnicalRoom/TechnicalAnnotationEditor.swift`
- `RoomScanner/Scan/TechnicalRoomScanView.swift`
- `RoomScanner/Domain/TechnicalRoom/TechnicalAlignmentSurvey.swift`
- `RoomScanner/Domain/TechnicalRoom/TechnicalCaptureJournal.swift`
- `RoomScanner/Domain/TechnicalRoom/TechnicalAnnotationHistory.swift`
- `RoomScanner/UI/RoomListView.swift`, `RoomScanner/UI/RootView.swift`, and `RoomScanner/MacUI/MacRootView.swift`
- `RoomScanner/Info-iOS.plist`, `RoomScanner/Info-macOS.plist`, and `project.yml` (new type registration only)
- `RoomScannerTests/TechnicalRoomPackageTests.swift`, `RoomScannerTests/TechnicalCaptureJournalTests.swift`, and `RoomScannerTests/TechnicalAnnotationTests.swift`
- `docs/TECHNICAL_ROOM_NEXT_TASKS.md`

Remaining physical T3/T4 checks: drag and snap points on real surfaces; verify pipe/duct/fitting/port placement; take and view survey photos; save, close, reopen and export a real survey; restore its world map and confirm annotation tools remain locked until the checkpoint passes. An unavailable iPhone blocks these checks, not the completed platform-independent storage tests. T5–T8 remain future milestones.

- Create `Documents/TechnicalRooms/<UUID>.technicalroom/` without changing existing room/house packages.
- Store metadata, technical-room JSON, survey/alignment data, raw mesh/geometry references, annotations, measurements, photos, and thumbnail.
- Support save, reopen, edit, export, and schema migration tests for the technical package.
- Keep the platform-independent portion readable by `RoomScannerMac` without importing ARKit or RoomPlan.

### 4. Viewer and validation (T5–T6)

- Build a dedicated technical-room viewer: orbit, top/front/side views, semantic filters, selection highlighting, dimensions, elevations, and raw-vs-annotated toggle.
- Add a validation report: five pipe lengths, three equipment dimensions, three repeats, three alignment checkpoints, interruption/relocalisation repeat.
- Keep `accuracyMm` null until each measurement is actually validated.

### 5. Recognition and exports (T7–T8)

2026-11-21 offline stability review:

- Fixed returning from app interruptions leaving the Technical Room camera paused: resume the same AR session/configuration without resetting tracking/anchors, and keep manual annotations locked until a new checkpoint. Returning from Camera Settings after initially denying access can start capture normally. Camera errors/settings access are visible in the primary capture section.
- AI-off MEP review no longer constructs Google sign-in/restore controls. Local photos expose Google Photos only after its disclosure is explicitly opened. Offline detection is not cancelled by Google account/mode changes; pending AI confirmation is dismissed when AI mode is disabled.
- Save now refuses an empty/no-budget mesh instead of silently writing a survey with no viewable geometry. Existing evidence is retained for retry.
- Kept the native content-first layout and made Take photo a prominent system action. House capture/session code is unchanged by this review.
- Verification: 213 macOS and 208 iOS simulator tests passed, including new camera resume/stop permission tests. Real iPhone camera interruption, colour coverage and physical measurement acceptance remain required before a production accuracy claim.

2026-11-21 Google AI / evidence increment:

- Implemented the Technical Room **Google AI mode** capture toggle and official Google Sign-In SDK for iPhone/Mac. It is not connected to a Google project yet; configuration fails visibly rather than pretending to sign in. House capture remains separate.
- AI mode retains calibrated camera JPEGs and corresponding raw depth/confidence while moving between viewpoints. Capture remains local; after saving, users explicitly select up to five images and confirm analysis. No automatic upload or pricing/subscription flow.
- Added on-device cylinder fitting as an offline option, and a separate Google-authenticated Gemini proxy service. Returned image masks are bound to image hashes and frame IDs, projected into local confident depth, then fitted into pipe/round-duct/rectangular-duct candidates. Recognition is a prototype; it is not broad equipment recognition or a validated MEP classifier.
- Added review/accept/reject/edit, Scan/MEP/Both viewing, sampled natural colours and user-selected material appearances. Accepted objects export separately as JSON/OBJ/USDZ/DXF; raw mesh and original manual annotations remain separate.
- Added **Take photo**, pinned local photos with camera-position markers, a Photos display toggle, and optional explicit copying to Google Photos with its own upload-only permission. Local photo bytes remain in the survey; stored Google Photos URLs are private to the owning account.
- Added a bounded optional evidence sidecar and JPEG assets plus a recognition sidecar; earlier `.technicalroom` packages still open. Explicit photos are not silently evicted. Camera transforms, image geometry, private URL boundaries and package image budgets are checked.
- Automated checks: full Mac suite 211/211, full iOS simulator suite 206/206, final focused Mac recognition/package checks 23/23, backend HTTP/authentication/limits/mask contract checks 10/10, and signed iPhone build passed. No real Gemini, Google login or Google Photos call was made; these require the user's project/client IDs/key and reachable HTTPS backend. New AR capture and 3D marker interaction still require physical-device acceptance.
- Setup and hosting guidance: `docs/GOOGLE_AI_SETUP.md`. The backend is deployable but not deployed; no paid resources or billing were enabled. Gemini project quota is shared across signed-in app users. Free usage is not inferred from Google sign-in.
- Native UI refinement: grouped system forms, compact Save navigation, SF Symbols, blue system controls, disclosed manual/alignment/diagnostic tools, and adaptive sheet sizing. Raw scans/photos can be saved without a reference frame; manual annotations still require verification. Mac library access is a visible sidebar entry and legacy packages use a native directory-capable import panel.
- Interactive Mac checks: imported the retained copy of the real phone survey, reopened its 3D view and native MEP form, ran offline fitting (one unreviewed cylinder-shaped candidate), and verified the unconfigured Google button presents a setup notice. No candidate was accepted as a confirmed pipe. The 3D surface has a concise accessibility representation plus separate accessible controls/photo buttons.

2026-11-20 saved-scan and export increment:

- The real saved phone survey was copied read-only for diagnosis: 97 frame records, one depth snapshot and one mesh snapshot (~79,970 vertices) decode correctly. It has no recovery map or checkpoint; that prevents aligned AR resumption, not offline viewing.
- Saved surveys now open in a dedicated orbit/zoom mesh viewer, with a separate details tab and a visible Technical Rooms section in the main library. House capture and house package formats are unchanged.
- Future Technical Room captures sample camera YCbCr colours only where current LiDAR depth agrees with the projected mesh vertex. A bounded 5 mm colour cache collects different viewpoints every three seconds while tracking is normal; colours are baked into the saved mesh. No AR frame buffers are retained. Missing samples stay grey. This is sampled face colour, not photographic UV reconstruction; old surveys cannot recover scene colours from a thumbnail.
- Optional per-vertex sRGB samples extend `capture.json`; the new reader accepts earlier surveys without colours. Coloured snapshots are included in the existing retention budget and colour range/count validation. Older app builds should not be used to open newly coloured surveys.
- Export menu: full `.technicalroom` package, JSON (annotations/alignment/raw snapshots), OBJ (vertex-colour extension), USDZ (camera-coloured face texture), and metre-unit DXF 3DFACE mesh with Z-up CAD coordinates. OBJ vertex-colour support depends on the receiving CAD/3D application. CAD mesh exports are scan geometry, not solid/BIM reconstruction or engineering-certified measurements.
- Direct DWG export is not implemented: an appropriate licensed DWG writer is required. DXF is available for conversion in CAD software. No misleading renamed DWG file is produced.
- User confirmed no MEP model/dataset is available and asked to skip DWG. Recognition remains a separate future model/data project; DWG is excluded from this increment.
- Automatic MEP recognition is not implemented: no trained pipe/duct/component model or labelled training dataset is bundled. Existing manual annotations remain available; RoomPlan furniture recognition is not substituted for MEP recognition.
- Physical validation remains required for colour projection/coverage, performance, saved viewer interaction, and CAD application interoperability. Automated USDZ export/reopen and package round-trip checks do not establish live AR or measurement accuracy.
- Verification: final macOS suite 198/198 passed; iOS simulator suite 193/193 passed, followed by 17/17 focused package/mesh tests after the final DXF-colour and USDZ-metre-scale additions. The updated reader also reopened the unmodified phone-survey copy with all 79,970 vertices. The signed iPhone build passes; live hardware colour capture remains unverified.

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

