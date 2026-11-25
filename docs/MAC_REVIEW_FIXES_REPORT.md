# Mac review fixes — implementation checkpoint

Branch: `codex/mac-review-fixes`, based on `feat/mac-studio-editor`.
No push or merge was performed. AR Notes remains in its separate worktree.

Fixes 1–23 have code changes on this branch, with fix 16 split into three approved commits. The gesture-grouping claim in fix 16 was already handled at endDrag and was skipped. All Swift tests below are written but UNRUN; both Xcode scheme builds are NOT VERIFIED. Service pytest and localization validation actually ran; see current results below.

## Current status

The user approved continuation through the capture error-propagation change (13)
and the three smaller export/history steps (16a–16c). All numbered implementation
items are now addressed; actual Apple builds, native behaviour checks and profiling
remain required. No AR session/lifecycle configuration changed.

Fix 16's continuous drag/rotation grouping was already implemented through
`StudioSceneController.endDrag` and was not rewritten. The estimate of resident
history memory is conservative serialized size times four; it is not measured RSS.
Each undo/redo half has half the budget and still caps at 40 entries. Native
SceneKit/Model I/O serialization and ZIP compression may finish their current
operation before cancellation is observed. No performance/accuracy claim is made.

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
- Earlier checkpoint: strict localization found 20 baseline gaps. Fix 21 resolves them; the latest audit PASSED (1,055 keys, zero missing German/unextracted literals), and a Python format-argument parity check passed. LocalizationCoverage XCTest remains UNRUN.
- Python unittest discovery under Scripts: ZERO TESTS FOUND on this branch; no tests passed from this command.
- Earlier checkpoint: pytest was unavailable. The requested development runner and existing pinned service requirements were subsequently installed in ignored `.worktrees/service-tests-env`. The latest service run PASSED: 13 distinct tests, one existing Starlette/httpx deprecation warning. No provider calls, credentials or real AI accuracy were tested.
- `xcodegen generate` and both `xcodebuild ... test` commands: command not found on Windows. Neither app has been built here.
- Fixes 1–12 did not edit capture sources. Fix 13 adds try to the capture save caller; no AR configuration/session code or Technical Room v1 schema/model changed. No new dependency was added.

## Limitations and review notes

- Native window delegate forwarding, quit cancellation, keyboard responder routing, concurrent windows, iCloud NSFileVersion materialization and package rollback require actual Mac validation. Device capture remains device validation pending; no accuracy or DIN claim is made.
- SceneEdit revision and modifiedAt are optional. Legacy files decode without them. A stale editor keeps the current file and writes a new independently identified conflict design with a suffixed title; raw source packages are untouched. Such a standalone copy retains its shell snapshot but does not gain a new physical scan package. Cloud house/design conflicts preserve the current version and copy unresolved versions rather than silently replacing current edits.
- Duplicate import uses one UUID map for house/structure identity, room identities, photo IDs/paths and matching neutral JSON references (including radiator room/house links). Binary/unknown assets and opaque room.json/structure-apple.json captures remain byte-for-byte evidence with original Apple IDs; raw evidence is not rewritten.
- Project deletion rolls back pre-commit moves on errors. Post-commit purge is best effort; sibling `.privacy-trash-<transaction>-<original-name>` items may remain for manual recovery. Process-crash transaction recovery still needs device/Mac validation.
- Fixes 16–23 are implemented in the continued commits below. CI has not run remotely: this branch is local and has not been pushed.

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

## Continued fixes 16–23

### fix(studio): bound undo history by estimated memory (16a)

Commit `a2f97e1`: **+52 / −5 lines**.

| File | Added | Removed |
|---|---:|---:|
| `RoomScanner/SceneEditing/SceneEditDocument.swift` | 27 | 5 |
| `RoomScannerTests/StudioHistoryBudgetTests.swift` | 25 | 0 |

Validation: StudioHistoryBudgetTests: estimated memory cap, count cap, undo/redo and branching. UNRUN.

### fix(studio): prepare exports and write files off main (16b)

Commit `caef5b1`: **+79 / −12 lines**.

| File | Added | Removed |
|---|---:|---:|
| `RoomScanner/SceneEditing/StudioExportPreparation.swift` | 22 | 0 |
| `RoomScanner/SceneEditing/StudioExporter.swift` | 42 | 12 |
| `RoomScannerTests/StudioExportPreparationTests.swift` | 15 | 0 |

Validation: StudioExportPreparationTests: worker thread and JSON round-trip. UNRUN.

### fix(studio): add export progress and cancellation (16c)

Commit `9db8bb4`: **+50 / −9 lines**.

| File | Added | Removed |
|---|---:|---:|
| `RoomScanner/SceneEditing/StudioEditorView.swift` | 20 | 6 |
| `RoomScanner/SceneEditing/StudioExportPreparation.swift` | 2 | 1 |
| `RoomScanner/SceneEditing/StudioExporter.swift` | 13 | 2 |
| `RoomScannerTests/StudioExportPreparationTests.swift` | 15 | 0 |

Validation: StudioExportPreparationTests: pre-cancelled work and completion progress. UNRUN. Native file cleanup/cancellation remains manual.

### fix(export): require an explicit technical survey selection (17)

Commit `37ba55d`: **+42 / −6 lines**.

| File | Added | Removed |
|---|---:|---:|
| `RoomScanner/Export/OrganisedExportService.swift` | 12 | 6 |
| `RoomScanner/MacUI/OrganisedExportSheet.swift` | 12 | 0 |
| `RoomScanner/Resources/Localizable.xcstrings` | 1 | 0 |
| `RoomScannerTests/TechnicalExportLinkTests.swift` | 17 | 0 |

Validation: TechnicalExportLinkTests: same-name surveys cannot implicitly match. UNRUN.

### fix(export): stream bounded photos and honour cancellation (18)

Commit `ca2f1e1`: **+74 / −13 lines**.

| File | Added | Removed |
|---|---:|---:|
| `RoomScanner/Export/OrganisedExportService.swift` | 19 | 10 |
| `RoomScanner/MacUI/OrganisedExportSheet.swift` | 3 | 3 |
| `RoomScanner/Storage/SurveyPhotoExportSource.swift` | 36 | 0 |
| `RoomScannerTests/SurveyPhotoExportSourceTests.swift` | 16 | 0 |

Validation: SurveyPhotoExportSourceTests: metadata for 200 photos, bounded single-file copy. UNRUN.

### fix(export): identify app version and hash manifest items (19)

Commit `4e13685`: **+37 / −4 lines**.

| File | Added | Removed |
|---|---:|---:|
| `RoomScanner/Export/ExportChecksum.swift` | 16 | 0 |
| `RoomScanner/Export/OrganisedExportService.swift` | 7 | 4 |
| `RoomScanner/Resources/Localizable.xcstrings` | 1 | 0 |
| `RoomScannerTests/ExportChecksumTests.swift` | 13 | 0 |

Validation: ExportChecksumTests: empty/abc known SHA-256 vectors. UNRUN.

### fix(mac): resolve studio windows through active storage (20)

Commit `53db762`: **+12 / −16 lines**.

| File | Added | Removed |
|---|---:|---:|
| `RoomScanner/MacUI/MacStudioWindow.swift` | 11 | 16 |
| `RoomScanner/Resources/Localizable.xcstrings` | 1 | 0 |

Validation: MacStudioWindow uses SceneEditStore and actual storage locations. Manual iCloud/local/forced-root reopening UNRUN. The existing opening/failure labels already had German entries; only the missing-design message required a new entry.

### fix(localization): complete German Mac studio export labels (21)

Commit `070e029`: **+34 / −5 lines**.

| File | Added | Removed |
|---|---:|---:|
| `RoomScanner/Export/OrganisedExportService.swift` | 4 | 4 |
| `RoomScanner/MacUI/OrganisedExportSheet.swift` | 1 | 1 |
| `RoomScanner/Resources/Localizable.xcstrings` | 29 | 0 |

Validation: Strict localization audit PASSED, 1,055 keys; format argument parity PASSED. LocalizationCoverage XCTest UNRUN.

### fix(ai): share inflight requests and expire cache entries (22)

Commit `ae47471`: **+115 / −8 lines**.

| File | Added | Removed |
|---|---:|---:|
| `docs/GOOGLE_AI_SETUP.md` | 9 | 0 |
| `services/technical-google-ai/app.py` | 40 | 8 |
| `services/technical-google-ai/requirements-dev.txt` | 1 | 0 |
| `services/technical-google-ai/test_cache.py` | 65 | 0 |

Validation: Service pytest PASSED: 13 distinct tests, including concurrent success/failure sharing, oldest-first eviction, expiry and recognition-version invalidation. One Starlette TestClient/httpx deprecation warning.

### ci: test both Apple schemes and service on pull requests (23)

Commit `b77ab60`: **+81 / −0 lines**.

| File | Added | Removed |
|---|---:|---:|
| `.github/workflows/tests.yml` | 81 | 0 |

Validation: PR workflow added for both full Apple schemes, localization and service. NOT executed on GitHub; manual IPA workflow unchanged.

## Remaining validation and limits

- XcodeGen and both xcodebuild test commands were attempted again: commands unavailable on Windows. Neither scheme has been built here; all Swift tests are unrun.
- The service tests use mocked provider results only. No Google sign-in, deployed service or device-recognition success is claimed. Run a single service instance/worker until shared rate limits exist.
- Manifest checksums use Apple CryptoKit (system framework, no third-party library). pytest is a development-only runner explicitly required by the task; production requirements are unchanged.
- Organised ZIP photos are metadata plus paths until a bounded image read (at most 4 MiB) is copied. Existing photo-folder names/numbering are retained. Large photo memory/performance and cancelled-archive cleanup still require Mac measurements.
- Studio synchronous export API remains for existing callers/tests; Studio UI uses dataAsync. SceneKit build/write/Model I/O bridge remain main-actor operations. A newly created MDLAsset has a single worker owner during OBJ export. Validate this on the supported SDK.
- "StudioExport" signposts in the StudioExport category allow Instruments timing of the complete pipeline. No measurements have been recorded here.
- CI uses the default toolchain on macos-26, selects an available iPhone simulator from simctl JSON, runs both schemes separately and retains logs/results for three days. Runner reference: https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md .
