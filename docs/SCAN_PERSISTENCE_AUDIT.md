# Scan persistence audit — 25 November 2026

Baseline: `8d178dd`. Work branch: `codex/incremental-scan-persistence`.
This audit distinguishes code evidence from unverified device behavior.

## House and standalone room

`ScanCoordinator` owns one `ARSession` passed to `RoomCaptureView`. House starts
one uninterrupted RoomPlan capture and calls `stop(pauseARSession: false)` when
Finish is pressed. `receive(room:)` appends the final CapturedRoom to the in-memory
`capturedRooms` array and immediately runs StructureBuilder. There is currently
no per-room stop/restart loop, no automatic room boundary event wired up, and no
on-disk partial capture. Earlier assumptions that room-by-room capture already
exists are incorrect. Room and House share this coordinator, with different final
package paths.

`receive(structure:)` retains encoded structure, structure USDZ, and per-room
encoded CapturedRoom, parametric USDZ and mesh USDZ data simultaneously.
`ScanView.finishScan()` then assembles a HousePackage, radiator data, thumbnail and
photo assets before synchronous `RoomStore.saveHouse` writes it. Standalone room
capture similarly retains its raw capture and both USDZ representations until save.
`HouseSurveyPhotoCapture.assets` retains JPEGs in an in-memory dictionary until
final packaging; their registration happens at finish.

One shared ARSession provides a common world coordinate system. A genuine
room-by-room implementation must keep it running while stopping RoomPlan, persist
each processed room, then restart RoomPlan without resetting world tracking.
A recovered session cannot silently reuse those coordinates after an app restart:
ARWorldMap relocalization and an explicit alignment state are required.

## Technical room

`TechnicalRoomScanCoordinator` owns a separate ARSession and has no RoomPlan
session. Live mesh caches, journal, depth, evidence keyframes and survey photos
remain in memory. Snapshot budgets limit retained evidence but are not persistence.
`saveRecoveryMap()` archives ARWorldMap into `worldMapData` in memory; contrary to
the supplied assumption, it does not write a map to disk. `TechnicalRoomScanView`
collects a final mesh, depth and thumbnail and writes a TechnicalRoomPackage only
on Save. Its library saves packages in a detached task with staging/replacement.
Repeatedly saving that growing package would not implement changed-anchor deltas.

## Voice notes and failures

`NoteAudioRecorder` has a 60-second cap, permission flow, meter task and interruption
handling. Completed clips use VoiceNoteRecovery's durable outbox, then ARNoteStore.
They are project sidecars, not yet ScanSession media. An in-progress recording
killed before finalization is not guaranteed recoverable. Existing audio is kept
until replacement succeeds. Audio-session changes are visible in code; there is
no device evidence establishing why a camera might freeze during recording.

A crash before final package save currently loses House/room geometry and photos,
and Technik mesh, keyframes and map. Previously committed project voice notes can
survive. `PackageReplacement` provides staging, backup and rollback for packages;
`SafePackageRead` rejects unsafe package paths. These should be reused.

## Reported larger-House crash

A plausible memory peak occurs during StructureBuilder plus simultaneous USDZ,
mesh and photo retention. This is a hypothesis, not a proven OOM diagnosis: the
crash report inspected for the previous scan-launch failure was a SwiftUI missing
environment assertion, already fixed in 8d178dd. No memory-pressure termination
report for this larger-house failure has been analyzed.

There is also a separate CPU/geometry risk: WallJunctions.subtract decomposes
non-intersecting polygons instead of returning them whole, allowing repeated
fragmentation during wall/floor processing. Earlier full-suite work observed an
X-junction test stall. This needs a focused geometry fix and regression evidence;
background disk saving alone cannot establish that larger-house loading is fixed.

## Implementation boundaries

Step 1 is an independently testable, additive storage foundation, initially not
wired into capture or launch UI. Step 2 changes RoomPlan lifecycle behavior and
requires device validation; the specification explicitly requires stopping and
reporting at this boundary if that behavior cannot be tested. Uncommitted work
from before this specification was archived under `/tmp/dwalk-pre-spec-wip.patch`
and `/tmp/*Recovery*.pre-spec`; it is not part of this branch's implementation.

## Implemented continuation

The subsequent user instruction “all finished -- implement all” authorized
continuing beyond the earlier stop boundary. Steps 2–7 were implemented locally
on this branch; device validation remains separate from implementation.

- House now persists a processed room and its thumbnail before Next room. The
  application no longer keeps a growing CapturedRoom array during capture. One
  ARSession remains shared; Finish reads saved native rooms for StructureBuilder.
- Large-room live updates write one replacement partial per room. Conservative
  triggers are 15 seconds, 12 added geometry items, 512 KiB growth, and a 3-second
  minimum sampling interval. Lifecycle and memory-warning flushes bypass the normal
  thresholds. Encoded bytes, write milliseconds, resident memory and thermal state
  counters are exposed in capture state; tune them with a physical-device profile.
- Technik writes hashed new/changed anchor patches, removals and journal deltas.
  Sorted JSON makes hashes deterministic. Journal frame hashes handle timestamp
  origins changing. Final save and recovery compact deltas into the existing package.
- Photos and finalized voice notes are written to session media with capture
  metadata. House retains photo metadata, not a growing JPEG dictionary. Audio
  also uses the existing durable outbox before session publishing. Recording uses
  the existing 60-second recorder, interruption handling and 100 ms meter interval.
- Unfinished scans have Recover, Retry finishing and confirmed Discard actions.
  Promotion is serialized and idempotent. Existing library packages win over older
  drafts; failures retain the session. Recovered packages carry an additive partial
  flag and do not imply full capture or verified alignment.
- World-map candidates are stored locally. A read-only relocalization camera is
  behind `scan.experimentalRelocalization` (off by default). It never merges new
  geometry. A tracking candidate is not independently verified alignment.
- Native USDZ/mesh generation is deferred to export and cached outside source
  packages. Package writes run on workers. A separate wall-clipping fix avoids
  decomposing disjoint polygons and joins outer L corners with miter footprints.

The earlier missing-environment crash is distinct from a possible finish-time OOM.
The latter remains unproven without the larger-House termination report. No
microphone/camera freeze cause has been reproduced on a physical LiDAR device;
`CaptureAudio` logging records audio-category transitions without audio contents.

A focused simulator run passed 56 tests after fixing deterministic mesh hashes,
wall-corner footprints and the stale SVG floor-count assertion. The final test
results, exact commits and limitations are recorded in SCAN_PERSISTENCE_RESULTS.md.
Unrelated in-progress skill files were not changed. No new dependencies were added.
