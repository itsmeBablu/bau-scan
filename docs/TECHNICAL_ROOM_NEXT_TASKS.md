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

### 1. Finish T2 capture and alignment

- Add a durable in-memory capture journal for frame metadata, depth snapshots, mesh snapshots, timestamps, tracking state, and alignment status.
- Prevent the room reference frame from being silently replaced after annotations exist.
- Add a third alignment checkpoint workflow with residual error and a visible “unverified” state when tracking/relocalisation fails.
- Save and restore an `ARWorldMap` for interruption recovery; require a successful alignment check before accepting new annotations.
- Add tracking-quality, FPS, memory, low-light, and incomplete-depth warnings.
- Keep all ARKit code under the iOS target; Mac must compile without ARKit/RoomPlan dependencies.

### 2. Finish T3 manual annotation foundation

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

