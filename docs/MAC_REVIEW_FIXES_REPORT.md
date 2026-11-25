# Mac review fixes — implementation checkpoint

Branch: `codex/mac-review-fixes`, based on `feat/mac-studio-editor`.
No push or merge was performed. AR Notes remains in its separate worktree.

Fixes 1–15 were confirmed in the starting source and implemented in separate commits. None of findings 1–15 was already fixed. All Swift tests below are written but UNRUN; both Xcode scheme builds are NOT VERIFIED.

## Current review boundary

The user approved continuing at fix 13. Duplicate-ID error propagation through the
capture save caller is now implemented. No AR session/lifecycle configuration changed.

Fix 16 has three remaining concerns: splitting Studio export between main-actor
SceneKit work and worker preparation/file work; progress/cancellation; and estimated
undo-memory budgets. The gesture-grouping finding is already handled by
`StudioSceneController.endDrag`: only completion invokes onMove/onRotate.

The remaining fix 16 implementation is estimated at 190–230 changed lines including
UI, exporter integration and regression tests. The original request says **STOP and
report if a fix needs more than about 150 lines**. No fix 16 code was changed.
Suggested separately reviewable substeps:

1. "16a": Foundation estimated undo-memory budget and its tests (about 40–60 lines).
2. "16b": exporter preparation/file pipeline, retaining SceneKit-only work on main
   (about 90–120 lines).
3. "16c": progress, Cancel, cancellation cleanup and tests (about 60–80 lines).

Mac profiling cannot be performed here. No responsiveness, memory or cancellation
performance claim is made. Fixes 16–23 remain pending.

## Per-fix changes

### 1. fix(mac): use hashable design references in sidebar selection

Commit `cd73f7a`: **+64 / −6 lines** (includes tests/localization/checklist changes).

| File | Added | Removed |
|---|---:|---:|
| `RoomScanner/MacUI/MacAppState.swift` | 1 | 1 |
| `RoomScanner/MacUI/MacDesignDetail.swift` | 23 | 0 |
| `RoomScanner/MacUI/MacRootView.swift` | 11 | 5 |
| `RoomScanner/SceneEditing/DesignRef.swift` | 14 | 0 |
| `RoomScannerTests/DesignRefTests.swift` | 15 | 0 |

Tests: DesignRefTests: equality, hash deduplication, source/date changes. **UNRUN on Mac/iOS.**

### 2. fix(studio): share focused session key across app targets

Commit `e797d49`: **+11 / −2 lines** (includes tests/localization/checklist changes).

| File | Added | Removed |
|---|---:|---:|
| `RoomScanner/MacUI/MacAppState.swift` | 0 | 2 |
| `RoomScanner/{MacUI => SceneEditing}/StudioFocusedValues.swift` | 0 | 0 |
| `RoomScannerTests/StudioFocusedValuesTests.swift` | 11 | 0 |

Tests: StudioFocusedValuesTests: shared-key compile coverage. **UNRUN on Mac/iOS.**

### 3. fix(storage): replace room and house packages with rollback

Commit `eced137`: **+74 / −7 lines** (includes tests/localization/checklist changes).

| File | Added | Removed |
|---|---:|---:|
| `RoomScanner/Storage/HousePackage.swift` | 2 | 3 |
| `RoomScanner/Storage/PackageReplacement.swift` | 43 | 0 |
| `RoomScanner/Storage/RoomPackage.swift` | 2 | 4 |
| `RoomScanner/Storage/RoomStore.swift` | 2 | 0 |
| `RoomScannerTests/PackageReplacementTests.swift` | 25 | 0 |

Tests: PackageReplacementTests: failed rename preserves original; backup launch recovery. **UNRUN on Mac/iOS.**

### 4. fix(mac): guard dirty studio windows on close and quit

Commit `f5674ba`: **+89 / −6 lines** (includes tests/localization/checklist changes).

| File | Added | Removed |
|---|---:|---:|
| `RoomScanner/App/RoomScannerApp.swift` | 1 | 0 |
| `RoomScanner/MacUI/StudioWindowGuard.swift` | 74 | 0 |
| `RoomScanner/SceneEditing/StudioEditorView.swift` | 12 | 5 |
| `docs/MAC_TEST_CHECKLIST.md` | 2 | 1 |

Tests: Manual close/Cmd-W/Cmd-Q Save/Discard/Cancel and failed-save checks in MAC_TEST_CHECKLIST. **UNRUN on Mac/iOS.**

### 5. fix(studio): scope editing shortcuts to focused viewport

Commit `642bc5e`: **+59 / −35 lines** (includes tests/localization/checklist changes).

| File | Added | Removed |
|---|---:|---:|
| `RoomScanner/MacUI/MacMenuCommands.swift` | 6 | 2 |
| `RoomScanner/SceneEditing/SceneEditDocument.swift` | 12 | 0 |
| `RoomScanner/SceneEditing/StudioEditorView.swift` | 15 | 33 |
| `RoomScanner/SceneEditing/StudioFocusedValues.swift` | 5 | 0 |
| `RoomScannerTests/StudioNudgeTests.swift` | 20 | 0 |
| `docs/MAC_TEST_CHECKLIST.md` | 1 | 0 |

Tests: StudioNudgeTests: whole selection moves together and restores with one undo; manual text-field routing. **UNRUN on Mac/iOS.**

### 6. fix(privacy): stage project deletion before catalogue commit

Commit `386954f`: **+42 / −4 lines** (includes tests/localization/checklist changes).

| File | Added | Removed |
|---|---:|---:|
| `RoomScanner/Storage/ProjectPrivacyStore.swift` | 24 | 4 |
| `RoomScannerTests/ProjectPrivacyTests.swift` | 16 | 0 |
| `docs/MAC_TEST_CHECKLIST.md` | 2 | 0 |

Tests: ProjectPrivacyTests: injected second-move failure restores previous files and leaves index unchanged. **UNRUN on Mac/iOS.**

### 7. fix(import): preserve house assets and remap duplicate identities

Commit `c7a5f22`: **+85 / −14 lines** (includes tests/localization/checklist changes).

| File | Added | Removed |
|---|---:|---:|
| `RoomScanner/Storage/HouseImportCopy.swift` | 55 | 0 |
| `RoomScanner/Storage/RoomStore.swift` | 3 | 14 |
| `RoomScannerTests/HouseImportCopyTests.swift` | 27 | 0 |

Tests: HouseImportCopyTests: raw structure/USDZ retained, new IDs, structure and photo links. **UNRUN on Mac/iOS.**

### 8. fix(library): keep unreadable packages visible with recovery actions

Commit `cbf69c0`: **+115 / −4 lines** (includes tests/localization/checklist changes).

| File | Added | Removed |
|---|---:|---:|
| `RoomScanner/MacUI/MacRootView.swift` | 2 | 1 |
| `RoomScanner/Resources/Localizable.xcstrings` | 7 | 0 |
| `RoomScanner/Storage/LibraryProblem.swift` | 24 | 0 |
| `RoomScanner/Storage/RoomStore.swift` | 27 | 2 |
| `RoomScanner/UI/LibraryProblemRows.swift` | 28 | 0 |
| `RoomScanner/UI/RoomListView.swift` | 2 | 1 |
| `RoomScannerTests/LibraryProblemTests.swift` | 25 | 0 |

Tests: LibraryProblemTests: error classification, corrupt and future-schema packages remain visible. **UNRUN on Mac/iOS.**

### 9. fix(studio): preserve stale edits as revision conflict copies

Commit `0873739`: **+89 / −13 lines** (includes tests/localization/checklist changes).

| File | Added | Removed |
|---|---:|---:|
| `RoomScanner/Resources/Localizable.xcstrings` | 1 | 0 |
| `RoomScanner/SceneEditing/DesignRef.swift` | 1 | 1 |
| `RoomScanner/SceneEditing/SceneEditDocument.swift` | 29 | 4 |
| `RoomScanner/SceneEditing/StudioEditorView.swift` | 2 | 2 |
| `RoomScanner/Storage/ConflictResolver.swift` | 22 | 0 |
| `RoomScanner/Storage/RoomStore.swift` | 6 | 2 |
| `RoomScanner/Storage/UbiquityMonitor.swift` | 1 | 1 |
| `RoomScanner/UI/Projects/ProjectPinsView.swift` | 1 | 1 |
| `RoomScannerTests/SceneStudioTests.swift` | 3 | 2 |
| `RoomScannerTests/StudioConflictTests.swift` | 23 | 0 |

Tests: StudioConflictTests and updated SceneStudioTests: legacy decode, revision persistence, stale-writer copy. **UNRUN on Mac/iOS.**

### 10. fix(cloud): reject stale container activation after toggle

Commit `9e2b75b`: **+46 / −7 lines** (includes tests/localization/checklist changes).

| File | Added | Removed |
|---|---:|---:|
| `RoomScanner/Storage/CloudAvailability.swift` | 1 | 2 |
| `RoomScanner/Storage/RoomStore.swift` | 15 | 5 |
| `RoomScannerTests/CloudToggleRaceTests.swift` | 29 | 0 |
| `docs/MAC_TEST_CHECKLIST.md` | 1 | 0 |

Tests: CloudToggleRaceTests: delayed enable/initial discovery followed by disable. **UNRUN on Mac/iOS.**

### 11. fix(studio): derive stable distinct plan overlays per story

Commit `70a6ba5`: **+27 / −1 lines** (includes tests/localization/checklist changes).

| File | Added | Removed |
|---|---:|---:|
| `RoomScanner/SceneEditing/SceneEditDocument.swift` | 10 | 1 |
| `RoomScannerTests/StudioOverlayTests.swift` | 17 | 0 |

Tests: StudioOverlayTests: unique stable IDs for basement/ground/upper storeys after round-trip. **UNRUN on Mac/iOS.**

### 12. fix(studio): keep full object footprints on the active floor

Commit `1d74d28`: **+103 / −9 lines** (includes tests/localization/checklist changes).

| File | Added | Removed |
|---|---:|---:|
| `RoomScanner/Resources/Localizable.xcstrings` | 1 | 0 |
| `RoomScanner/SceneEditing/StudioPlacement.swift` | 75 | 9 |
| `RoomScannerTests/StudioFloorPlacementTests.swift` | 27 | 0 |

Tests: StudioFloorPlacementTests: L/U concavity, different floor extents and rotated footprint. **UNRUN on Mac/iOS.**

## Validation actually performed

- `git diff --check feat/mac-studio-editor..HEAD`: passed.
- Python plistlib parsed both app Info plist files.
- Added localization keys have English and German entries.
- `node Scripts/audit_localization.js --strict`: FAILED, 20 existing unextracted labels; zero missing German translations among catalog entries. All 20 labels are absent from the base catalog too. Pending fix 21 must resolve these; LocalizationCoverage XCTest is unrun.
- Python unittest discovery under Scripts: ZERO TESTS FOUND on this branch; no tests passed from this command.
- `python -m pytest services/technical-google-ai -q`: could not run, pytest is not installed. No dependencies were installed.
- `xcodegen generate` and both `xcodebuild ... test` commands: command not found on Windows. Neither app has been built here.
- Fixes 1–12 did not edit capture sources. Fix 13 adds try to the capture save caller; no AR configuration/session code or Technical Room v1 schema/model changed. No new dependency was added.

## Limitations and review notes

- Native window delegate forwarding, quit cancellation, keyboard responder routing, concurrent windows, iCloud NSFileVersion materialization and package rollback require actual Mac validation. Device capture remains device validation pending; no accuracy or DIN claim is made.
- SceneEdit revision and modifiedAt are optional. Legacy files decode without them. A stale editor keeps the current file and writes a new independently identified conflict design with a suffixed title; raw source packages are untouched. Such a standalone copy retains its shell snapshot but does not gain a new physical scan package. Cloud house/design conflicts preserve the current version and copy unresolved versions rather than silently replacing current edits.
- Duplicate import uses one UUID map for house/structure identity, room identities, photo IDs/paths and matching neutral JSON references (including radiator room/house links). Binary/unknown assets and opaque room.json/structure-apple.json captures remain byte-for-byte evidence with original Apple IDs; raw evidence is not rewritten.
- Project deletion rolls back pre-commit moves on errors. Post-commit purge is best effort; sibling `.privacy-trash-<transaction>-<original-name>` items may remain for manual recovery. Process-crash transaction recovery still needs device/Mac validation.
- The export performance/undo-memory work (16), explicit technical export links (17), streaming/cancel (18), manifest checksums (19), window paths (20), localization gaps (21), service cache concurrency (22), and PR CI (23) remain pending.

## Continued fixes 13–15

### 13. fix(house): reject duplicate room identities with a typed error

Commit `582bf5e`: **+42 / −31 lines**.

| File | Added | Removed |
|---|---:|---:|
| `RoomScanner/Domain/HouseBuilder.swift` | 7 | 2 |
| `RoomScanner/Scan/ScanView.swift` | 1 | 1 |
| `RoomScanner/Storage/HousePackage.swift` | 2 | 2 |
| `RoomScanner/Storage/RoomStore.swift` | 1 | 1 |
| `RoomScannerTests/HouseBuilderTests.swift` | 15 | 9 |
| `RoomScannerTests/HousePackageTests.swift` | 2 | 2 |
| `RoomScannerTests/HouseRadiatorTests.swift` | 3 | 3 |
| `RoomScannerTests/LevelExportTests.swift` | 2 | 2 |
| `RoomScannerTests/ProjectReportTests.swift` | 1 | 1 |
| `RoomScannerTests/RealHouseTests.swift` | 3 | 3 |
| `RoomScannerTests/RevitIFCExportTests.swift` | 1 | 1 |
| `RoomScannerTests/SceneStudioTests.swift` | 4 | 4 |

Tests: HouseBuilderTests duplicate IDs produce BuildError; existing fixtures/callers updated. Two nonthrowing fixture factories use try! for known-valid synthetic inputs only. No duplicate-key dictionary initializer remains in app sources. **UNRUN on Mac/iOS.**

### 14. fix(storage): bound package reads and reject symlinks

Commit `faa793c`: **+72 / −28 lines**.

| File | Added | Removed |
|---|---:|---:|
| `RoomScanner/Storage/HousePackage.swift` | 5 | 5 |
| `RoomScanner/Storage/RoomPackage.swift` | 10 | 10 |
| `RoomScanner/Storage/SafePackageRead.swift` | 35 | 0 |
| `RoomScanner/Storage/SurveyPhotoStore.swift` | 2 | 6 |
| `RoomScanner/Storage/TechnicalRoomPackage.swift` | 1 | 7 |
| `RoomScannerTests/SafePackageReadTests.swift` | 19 | 0 |

Tests: SafePackageReadTests: per-file size, entry/total budgets and internal symlinks. **UNRUN on Mac/iOS.**

### 15. fix(storage): retry house migrations after failed writes

Commit `12b1f7e`: **+37 / −6 lines**.

| File | Added | Removed |
|---|---:|---:|
| `RoomScanner/Storage/RoomStore.swift` | 14 | 6 |
| `RoomScannerTests/HouseMigrationRetryTests.swift` | 23 | 0 |

Tests: HouseMigrationRetryTests: corrupt structure remains visible with lastError and retries after repair. Existing snapshot-only legacy houses update metadata after a successful write. **UNRUN on Mac/iOS.**


Continuation validation: diff whitespace checks, plist parsing and Foundation-only imports passed. The strict localization audit still reports the same 20 baseline gaps. XcodeGen and both scheme test commands were attempted again and were unavailable on Windows. All added Swift tests remain unrun. Safe package limits are 10,000 entries, 1 GiB per package tree, 256 MiB per ordinary file, 1 MiB for meta.json, and existing tighter technical/photo limits. Oversized or symlink-bearing packages are rejected rather than partially loaded.
