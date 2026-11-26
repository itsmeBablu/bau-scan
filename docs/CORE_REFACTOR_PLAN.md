<!-- Local execution status, 2026-11-26 -->

## Local execution and handoff status

- User override: implement locally; do not pull, push, open a PR, or trigger remote changes. The original remote instructions below are retained as the supplied plan, not executed.
- Working branch: `codex/core-consolidation`, based on `015dbdb81e57d74fa959348162cca7f95cae70e5`.
- Phase G remains UNVERIFIED. The user explicitly revised the implementation gate on 2026-11-26: "Yes—implement locally; Mac verification later". Local implementation may proceed; this does not waive Mac, CI or device acceptance checks.
- Existing local evidence: `.worktrees/core-phase-g-015dbdb.json`, recorded on the clean base commit. Localization, Node regressions, style, Python service, plist syntax and whitespace checks passed there; Apple schemes were blocked. This is not evidence for subsequent edits.
- Follow `runChecks.md` at the repository root on the Mac. Keep full logs and exact checkout identity; local Mac results must not be described as GitHub CI.
- The read-only inventory below records the unchanged base. Subsequent implementation is recorded separately in this plan and the QA report; do not interpret the inventory's +0/-0 as the final diff.
- Resume Phase G verification with Mac results. No passing Apple build, CI or device result is asserted for the local implementation.

---

## Preliminary read-only inventory — 2026-11-26

The user subsequently authorized other safe work while Mac checks are pending.
This is source inspection only, not completion of Phase 0A or permission to bypass
Phase G. All references below describe base `015dbdb`; production files are unchanged.
No runtime or performance conclusion follows from these counts.

### Recount method and results

Count every `*.swift` recursively under the named root, using UTF-8 decoding and
`splitlines()` (blank lines and comments included). Generated Xcode files,
dependencies, scripts, localization and documentation are excluded. Both test
targets use `RoomScannerTests` sources in `project.yml:160` and `project.yml:267`;
there is no separate `RoomScannerMacTests` directory to count again.

| Measure | Observed value | Interpretation |
| --- | --- | --- |
| Production Swift | 252 files / 28,768 lines | Source size, not complexity or performance |
| Shared test Swift | 99 files / 7,200 lines | Existence does not mean tests ran |
| `Task.detached` lexical occurrences | 87 | Each needs ownership/cancellation review, not automatic replacement |
| `try?` lexical occurrences | 117 | Regex `\btry\?`; not a parsed Swift error-handling audit |
| `@MainActor` lexical occurrences | 111 | Includes annotations; not a count of types or main-thread violations |
| `OSSignposter` identifier occurrences | 1 | Existing Studio export interval only |
| `import MetricKit` occurrences | 0 | No integration found by this search |
| XCTest metric identifiers requested by plan | 0 | No `XCTClockMetric`, `XCTMemoryMetric`, `XCTCPUMetric` found |

The original plan's approximate `try?` number is not reproduced by this lexical
method. A raw substring count is 136 and includes text that is not necessarily a
Swift `try?` expression; neither count establishes a swallowed-error defect.

Largest production files: `SceneEditing/StudioEditorView.swift` 938 lines;
`Scan/TechnicalRoomScanView.swift` 697; `SceneEditing/SceneEditDocument.swift` 663;
`Export/PlanRenderer.swift` 602;
`TechnicalRoom/Capture/TechnicalRoomScanCoordinator.swift` 600;
`Viewer/ViewerView.swift` 595; `Export/OrganisedExportService.swift` 457;
`SceneEditing/StudioViewport.swift` 450; `UI/Projects/RenovationNavigation.swift` 439;
`Storage/RoomStore.swift` 422. Size alone does not justify splitting these files.

### Responsibility inventory and proposed ownership

Paths in this table are relative to `RoomScanner/`. These are investigation
candidates, not confirmed bugs. Keep platform/capture differences intentional.

| Responsibility / source evidence | Existing authority and overlap | Proposed work after gates | Risk / owning phase |
| --- | --- | --- | --- |
| Package replacement: `Storage/PackageReplacement.swift:4`, `Storage/TechnicalRoomPackage.swift:106` | Room/house writers call shared commit; technical writer has coordinated staging/backup/rollback of its own | Compare contracts before extracting only proven common pieces | High: recovery directory naming differs; Phase 2 |
| Recovery: `Storage/PackageReplacement.swift:14`, `Storage/TechnicalRoomLibraryStore.swift:24` | Shared recovery uses target-specific `.package-backup`; technical recovery reads `.technical-backup-*` to identify destination | Preserve both legacy recovery forms and interrupted-write tests | High: backup retention and target validation; Phases 0B/2 |
| Safe reads: `Storage/TechnicalRoomPackage.swift:180`, `Storage/RoomPackage.swift:80`, `Storage/HousePackage.swift:72` | All already reuse `SafePackageRead` | Keep this authority; do not add another package-reader abstraction | Security/compatibility; Phase 2 |
| Catalogue enumeration: `Storage/RoomStore.swift:213`, `Storage/TechnicalRoomLibraryStore.swift:12`, `UI/Projects/RenovationWorkspace.swift:100` | Multiple consumers enumerate package metadata; workspace combines library roots and derives references | Characterize ordering, identity, warnings, offline items and invalidation before sharing enumeration | High: local/iCloud visibility and stale state; Phase 2 |
| Export publication: `Export/Projects/ProjectArtifactGenerator.swift:8`, `Storage/ProjectArtifactIndex.swift` | Existing request identity, metadata checks, coordinated publication and content reuse | Reuse existing generator/index; compare other export entry points before consolidation | High: filenames, cancellation and durable reuse; Phases 1/4 |
| Legacy export writer: `Storage/ProjectReportLoader.swift:64` | `ProjectArtifacts.save` writes UUID filenames; direct qualified call search finds tests only | Keep legacy characterization tests; check references/indirection before removal | No demonstrated production duplication from this writer; Phases 1/7 |
| Summary caches: `Storage/ProjectScanSummaryCache.swift:5`, `Storage/ProjectEvidenceSummaryCache.swift:4` | Geometry summary and evidence metadata have distinct data/invalidation needs | Verify invalidation tests and measure repeated decoding before combining anything | Stale summaries and memory; Phases 0A/2/6 |
| Photo thumbnails: `UI/Projects/ProjectPhotoLibraryView.swift:4` | Existing actor owns NSCache, limited to 48 entries / 12 MiB cost | Inventory other thumbnail readers; measure before replacing current bounded cache | Image decoding/lifetime; Phases 3a/6 |
| Photo ZIP paths: `Export/Projects/PhotoArchiveLayout.swift:4` | Existing shared path state handles floor/room identity and numbering | Pin existing archive outputs before changing adapters | Export compatibility; Phases 0B/3a/4 |
| Audio playback: `Notes/NotePlayback.swift:5`, `Notes/AudioWaveformCache.swift:6` | Shared playback arbitration and waveform cache already exist | Audit recorder/save/retry separately; preserve RoomPlan audio policy | Capture/audio ownership; Phase 3a |
| Markers: `Viewer/AnnotationIcon.swift:12` | Shared glyph renderer already exists | Trace SceneKit/RealityKit adapters before proposing common descriptors | Coordinate/hit-target regression; Phase 3a |
| Instrumentation: `SceneEditing/StudioExporter.swift:12` | Studio export already has a signpost interval | Extend existing instrumentation only after build gate; no duplicate instrumentation family | Privacy and measurement overhead; Phase 0A |

Recovery review point: `PackageReplacement.recover` removes the backup when the
target exists, without validating the target in that function. This is not proof
of data loss: caller ordering and interrupted/corrupt-target fixtures must establish
the reachable behavior first. Do not generalize this policy to technical packages
or remove recovery files during this audit.

### Existing safety coverage to execute, not recreate

- `RoomScannerTests/PackageReplacementTests.swift:5`: failed rename / launch recovery.
- `RoomScannerTests/TechnicalRoomPackageTests.swift:84`: independent round trip;
  `:102` invalid overwrite; `:111` failed swap; `:199` interrupted backup recovery.
- `RoomScannerTests/ProjectArtifactReuseTests.swift:5`: unchanged request/source change;
  `:57` content reuse; `:73` concurrent publication; `:91` stale metadata.
- `RoomScannerTests/ProjectScanSummaryTests.swift:15`: changed/unavailable summary invalidation.
- `RoomScannerTests/ProjectEvidenceSummaryTests.swift:5`: notes invalidate metadata cache.
- `RoomScannerTests/DesignSystemTests.swift:36`: token appearance;
  `:41` contrast; `:54` accessible sizes and reduced-motion policy.

All Swift coverage above remains UNRUN here. Full ownership/error tables, golden
coverage gaps, sanitizers, warnings, performance datasets and instrumentation are
still pending. No bug severity or performance improvement is claimed from lexical
inspection. Production change for this inventory: +0/-0; no tests added or changed.

## Preliminary safety-net review — part 2, 2026-11-26

Read-only review of test bodies and fixture inventory, not a test execution or
completion of Phase 0B. References below are relative to `RoomScannerTests/`.
"Gap" means the requested guarantee was not established by the inspected tests;
it is not an assertion that no related test exists anywhere.

| Required guarantee | Existing source coverage | Remaining evidence or gap |
| --- | --- | --- |
| PDF / PNG output | `ExportServiceTests.swift:48`, `PlanRendererTests.swift:44`, `:53` | Headers, dimensions/ink and PDF structure are checked; no reviewed visual golden baseline established |
| DXF / SVG output | `DXFExporterTests.swift:19`, `:31`, `:40`; `SVGExporterTests.swift:7`, `:13`, `:20` | Structural/layer/unit assertions exist; not a complete golden snapshot of every exported entity |
| OBJ / STL / PLY | `MeshWritersTests.swift:7`, `:22`, `:31`; `PlanMeshBuilderTests.swift:20`, `:42`, `:51` | Writer layouts, geometry counts/bounds/normals exist; approved complete output goldens still needed |
| Room JSON / resolved geometry | `HousePackageTests.swift:218`; `ResolvedGeometryExporterTests.swift:8`, `:34` | Compatibility, determinism, quantities/provenance assertions exist; pin representative full payloads without changing schemas |
| IFC | `RevitIFCExportTests.swift:16`, `:53`, `:69`, `:103`, `:127`; fixture `Fixtures/TechnicalRoom/revit-ifc-counts.json` | Semantic count snapshots and deterministic output exist; not Revit interoperability or full STEP golden evidence |
| Raw USDZ preservation | `ExportServiceTests.swift:70`; `TechnicalRoomPackageTests.swift:42` | Copy and portable mesh tests exist; physical RoomPlan capture remains device validation pending |
| ZIP layout / manifest / photo privacy | `ArchiveExporterTests.swift:40`, `PhotoArchiveTests.swift:5`, `:23`, `:41`; `SelectedPhotosExporterTests.swift:8`, `:38`; `PhotoExportPrivacyTests.swift:8`; `PhaseOneExportSafetyTests.swift:35`, `:45` | Broad assertions already exist. Archive listing in `ArchiveExporterTests` is macOS-conditional; inspect both schemes' effective coverage before adding duplicate tests |
| Failed/cancelled archive publication | `PhaseOneExportSafetyTests.swift:14` | Prior ZIP preservation covered in source; run before refactoring publication |
| Room / house / technical package round trips | `RoomPackageTests.swift:66`, `HousePackageTests.swift:29`, `TechnicalRoomPackageTests.swift:84` | Run existing coverage; augment representative legacy/backup fixtures only after build gate |
| Stage/replace failure and recovery | `PackageReplacementTests.swift:5`, `TechnicalRoomPackageTests.swift:111`, `:199` | Injected rename/swap and manually created interrupted states exist; this does not prove real process termination at every transaction boundary |
| Session checkpoint boundaries | `ScanSessionStoreTests.swift:6`, `:49`; `ScanSessionIntegrationTests.swift:55`, `:63`, `:95` | Fault injection and delta/recovery behavior exist; retain these when unifying transaction code |
| Durable notes / stale drafts | `UIRedesignBaselineTests.swift:13`, `:24`, `:45`, `:56`; `ProjectDetailsTests.swift:4`, `:22`; `ARNoteTests.swift:79`, `:113` | Store reload/conflict/recovery assertions exist; actual editor close, tab switch, relaunch and finalization UI sequence still unverified |
| Audio rerecord / recovery | `WrittenNoteTests.swift:33`, `VoiceNoteRecoveryTests.swift:5`, `:41`, `:58`; `ScanSessionStoreTests.swift:63` | Old-media retention and stale recovery cases exist; live mic/interruptions require device evidence |
| Local/iCloud identity / cache invalidation | `UIRedesignBaselineTests.swift:34`, `ScanVoiceNoteLibraryTests.swift:5`, `ProjectScanSummaryTests.swift:15`, `ProjectEvidenceSummaryTests.swift:5` | Source identity and revision invalidation exist; real undownloaded iCloud packages and sync races remain unverified |
| Concurrent writers | `ProjectArtifactReuseTests.swift:73` | Export publication concurrency has a test. This cannot establish concurrent-writer safety for every package writer |
| Disk full / real process kill | Existing injected generic I/O faults are partial coverage | Explicit ENOSPC at each write stage and subprocess termination/restart matrix not established; generic thrown errors are not equivalent |

Fixture inventory found the real house and dining-room scans, synthetic Swift
fixtures, three Technical Room v1 samples and IFC semantic-count snapshots.
No new fixtures or golden expectations were created or accepted in this review.
Do not regenerate goldens from unbuilt output and call them validated.

Priority after a green build: (1) run the existing suite before adding overlap;
(2) close transaction failure/recovery gaps; (3) establish approved export goldens;
(4) test UI-visible durable notes and offline catalogue behavior. Preserve all
existing assertions. Production/test code +0/-0 for this read-only part.

## Preliminary concurrency/error review — part 3, 2026-11-26

This is a prioritized source trace, not the exhaustive Phase 1 audit or a runtime
finding. No source change is authorized by this table before the build gate.
Paths are relative to `RoomScanner/`. Test proposals are for the post-gate work;
they have not been added or run.

| Path and owner | Observed execution / error policy | Decision and required evidence |
| --- | --- | --- |
| `UI/ExportSheet.swift:181` — view-owned generation task | Detached worker has explicit cancellation forwarding via `withTaskCancellationHandler`; result/error requires current request identity and non-cancelled task; disappearance cancels at `:84` | Reuse this established ownership pattern. Verify stale completion and cancelled worker tests before sharing orchestration |
| `Export/Projects/ProjectArtifactGenerator.swift:8` — caller-owned async generation | Existing metadata and content identity checks surround publication; cancellation checked at `:26`; scratch cleanup uses optional `try?` | Keep source/metadata guards. Test cancellation before and during slow synchronous phases; explicit worker ownership is the caller's responsibility |
| `Notes/ProjectVoiceNotesView.swift:152` — view timeout task | After 30 seconds, sets `busy = false` and displays a retry message. This block does not cancel the unstructured operation tasks started at `:204`, `:231`, `:254`, `:273` | Priority investigation: hold an injected worker beyond timeout, retry, and prove whether operations overlap or stale completion changes UI. Do not equate timeout with cancelled/durable failure; preserve recovery copies |
| `Notes/ProjectVoiceNotesView.swift:190` — reload caller | First detached index result checks cancellation, visibility and root at `:194`; second recovery-count read at `:197` has no equivalent guard after its suspension | Test navigation/root change while second read is delayed. If reproduced, use request identity on all result applications; do not discard durable worker output |
| `Storage/TechnicalRoomLibraryStore.swift:12` — MainActor store | `reload()` performs directory creation/enumeration, recovery and manifest decoding synchronously; `save` awaits off-main package write then calls reload | Source confirms main-actor I/O, not its latency. Measure a large catalogue and recovery backup before changing ownership; retain warnings and local identity |
| `Storage/TechnicalRoomLibraryStore.swift:26` — recovery helper | Optional directory listing falls back to an empty list, while per-backup read failures become warnings at `:34` | Test listing failure separately from no backups; decide whether an actionable warning is needed. Do not treat every cleanup/optional read as a critical save failure |
| `Scan/ScanCoordinator.swift:178` — coordinator checkpoint task | Active/scanning/single-task guards precede conversion in a detached worker at `:192`; minimum spacing and checkpoint policy already exist | Keep capture engines separate. Prove cancellation/old-session completion and frame/object lifetime in tests and on device before altering capture |
| `Scan/CaptureBackgroundFlush.swift:19` — MainActor background-task wrapper | OS expiration callback ends the background token; operation itself is awaited and is not cancelled by that callback | Test expiration during a delayed save and report durable completion/recovery state; ending background time is not proof the save succeeded. Device validation pending |
| `Notes/NotePlayback.swift:5` — shared MainActor arbitration | Weak active player and latest-request token; tick task uses weak self, cancellation guard after sleep, explicit stop | Preserve single-playback policy. Test navigation, simultaneous requests, recording overlap and audio-category restoration; simulator cannot validate RoomPlan mic policy |
| `Storage/ScanSessionStore.swift:24` — actor | Serialized instance methods and fault points after payload/index/manifest at `:119`–`:122`; stage cleanup is optional | Existing fault tests are valuable. Actor isolation serializes one instance only: investigate two store instances writing the same root before claiming cross-instance safety |

Task lexical hotspots for a later full ownership audit: voice-note library 9;
House coordinator 5; Studio editor 5; technical coordinator 4. Three occurrences
each appear in the voice player sheet, House scan view, technical library store,
and technical library view. These counts do not establish a defect or justify
blanket conversion to structured concurrency.

Optional-`try?` hotspots by the same lexical method: `Viewer/PlanSceneBuilder.swift`
7; `SceneEditing/StudioEditorView.swift` 6; `Export/ExportService.swift` 5;
`Notes/NoteAudioRecorder.swift` 4; `UI/HouseDetailView.swift` 4. Each expression
needs its own critical-versus-optional error classification. Sleep cancellation and
best-effort temporary cleanup must not be rewritten as user-visible save failures.

### First focused regressions to add after Phase G

1. Delayed voice operation crosses timeout; retry cannot overlap publication or
   clear a newer operation's busy state; late results cannot update another screen.
2. Delay recovery-count read, navigate/change notes root, then finish it; no stale
   count or error appears in the new context.
3. Two independent session-store instances contend for one package; recovery retains
   the last committed payload/index/manifest and all referenced media.
4. Recovery enumeration failure remains distinguishable from a successfully empty
   backup list; old backups remain intact.
5. Simulate background expiration during checkpoint writes, reopen the session,
   and verify actual durable state rather than relying on an ended OS token.

These are test designs, not passing tests or confirmed user-visible defects.
The complete 87-task/117-optional-try/111-MainActor review remains outstanding.
Production/test code +0/-0 for this part. No performance numbers, Apple test
results, device results or standards-compliance claims were generated.

## Original supplied plan (preserved)

# dWalkScan / bau-scan - CORE CONSOLIDATION, STABILITY AND PERFORMANCE PLAN (v2)

Repository: itsmeBablu/bau-scan. Starting point: main at 015dbdb. Work branch:
codex/core-consolidation. Open a pull request into main; DO NOT push to main directly,
and never merge a PR whose CI is red. Read first: ARCHITECTURE_EN.md, docs/WORK_QUEUE.md,
docs/QA_VALIDATION_REPORT.md, docs/REGRESSION_AUDIT.md, docs/FOUND_BUGS.md,
docs/DEVICE_TEST_CHECKLIST.md, docs/CAMERA_VOICE_PIN_RESULTS.md. Search by symbol.

==================== PART A - GOAL, SCOPE, RULES ====================

GOAL
Same functionality, safer data, fewer duplicated implementations of the same
responsibility, measured performance. Priority: 1 data integrity, 2 stability,
3 correct functionality, 4 simple native UX, 5 reuse, 6 performance, 7 code size.
There is NO line-count target.

CURRENT STATE (re-verify at start; do not redo what exists)
 - Many features from the UI/design/core prompts are already in main but UNBUILT and
   UNTESTED (the QA doc lists all Swift tests, both Apple builds and XcodeGen as UNRUN):
   design tokens + style audit ratchet, scan organisation, project dashboard, scoped
   project preferences, photo gallery with bounded thumbnails, inline voice rows,
   explicit export generation + reuse, note stale-write conflict. Treat all of these as
   "implemented, unverified". Verify and fix; do not rebuild.
 - ~28,800 production Swift lines, 252 files, 7,200 test lines. 87 Task.detached,
   135 try?, 111 @MainActor. No performance tests. Almost no signposts.
 - TechnicalRoomPackage has its own replacement logic (no PackageReplacement).
 - ProjectArtifacts.save still names files UUID().ext: confirm whether any path still
   uses it.
 - Last commit documented as built, tested and installed on iPhone: 59ee4e0
   (tag last-verified-59ee4e0). Snapshot of the unbuilt state: tag unbuilt-snapshot-015dbdb.

OUT OF SCOPE: new screens or features. This plan verifies, hardens and consolidates.

PRINCIPLES
Single source of truth; reuse before adding; smallest architecture that works (no
protocol+manager+coordinator+repository per operation); native Apple frameworks only;
offline-first; backward-compatible persistence; evidence-based optimisation. Keep
differences needed for correctness (RoomPlan vs ARKit, SceneKit vs RealityKit,
format-specific writers).

HARD RULES
1. No new runtime dependencies (dev-only tools are fine if not shipped).
2. Preserve features, scan packages (.roomscan/.housescan/.technicalroom), UUIDs, raw
   AR coordinates, local/iCloud identity, checkpoint/recovery behaviour, privacy
   protections, EN/DE localisation, iOS 18+/macOS 15+.
3. No persistent format/schema change without proposal + migration + backup + rollback
   + legacy-fixture tests + MY approval.
4. Never delete user files or recovery data automatically. Never delete or weaken tests,
   recovery or validation code. No new feature commits while CI is red.
5. Never restart/reconfigure the AR session or toggle the audio session from UI code.
6. EVIDENCE RULE: verified = passing test or CI/device log for the exact commit SHA.
   Else write UNVERIFIED. Compiling is not proof of behaviour; simulator is not proof of
   camera/mic/LiDAR/thermal behaviour ("device validation pending" + exact steps in
   docs/DEVICE_TEST_CHECKLIST.md). No performance claim without before/after numbers
   from the same test. Never disable tests, loosen assertions or bypass checks.
7. CI ROUTE: this environment cannot build Apple targets. Use GitHub Actions
   (tests.yml, workflow_dispatch or PR). If you cannot trigger CI or read its logs,
   STOP and tell me exactly what I must run and paste. Never report a phase complete
   without a CI run on its final commit.
8. One logical commit group per phase, small commits, phase report, then STOP for my
   approval. Do not start the next phase. Stop at once if a migration, destructive
   operation or capture-engine change is needed.
9. Docs: update existing documents; no new overlapping reports. Only additions:
   docs/CORE_REFACTOR_PLAN.md (this plan) and baseline tables in the existing QA doc.

==================== PART B - PHASES (start with Phase G only) ====================

PHASE G - BUILD GATE (before anything else)
 - Create the branch from main. Run tests.yml on it. Required green: RoomScanner (iOS),
   RoomScannerMac, strict localisation audit, style audit, Python service tests.
 - Fix every compile error and failing test with the smallest change. No refactors, no
   new features. Group fixes by cause in the report.
 - If failures are widespread (more than a few distinct root causes), STOP and report
   them so I can choose: fix forward, or branch from tag last-verified-59ee4e0 and
   re-apply the later commits in small CI-verified batches.
 - Report: run URL, SHA, Xcode/Swift/runner/simulator versions, counts, failures fixed.
 - Then list every "implemented, unverified" feature from CURRENT STATE with the test
   that now covers it (or "no test yet").

PHASE 0A - MEASURE (no behaviour change)
 - Read-only inventory: location, duplicated responsibility, authoritative
   implementation, proposed consolidation, regression risk, owning phase. Include
   unused code, unreachable navigation, repeated loading/saving/decoding/validation,
   repeated tasks, silent errors, data-loss and privacy risks. Re-count production LOC
   (production only), largest files, warnings.
 - Instrumentation: OSSignposter intervals for launch-to-first-screen, catalogue load,
   dashboard load, scan finalisation, package write/replace, export generation, photo
   capture, voice-note save, Studio scene build, plan render. MetricKit subscriber
   (launch, hangs, memory, disk writes); no user content in logs.
 - Performance tests (XCTClockMetric/XCTMemoryMetric/XCTCPUMetric) on a synthetic
   fixture generator (e.g. 20 projects, 200 scans, 500 photos, 50 audio files, one
   large mesh): catalogue load, dashboard stats, 200-photo export peak memory, PDF
   render, house build.
 - CI additions: Thread Sanitizer + Address Sanitizer test runs; SWIFT_STRICT_CONCURRENCY=
   complete as a warning-count RATCHET; build-warning ratchet; code coverage; weak-
   reference/deinit leak tests for stores, coordinators, recorders, playback objects.
 - Record baselines (numbers, environment, dataset) in the QA doc. Budget = baseline or
   better; no invented numbers.

PHASE 0B - SAFETY NET (before any refactor)
 - Golden-output tests pinning CURRENT behaviour: every export format, ZIP layout and
   manifest, package round trips, legacy fixtures (room, house, technical room incl.
   backup directories), note and audio persistence, catalogue results, geometry
   quantities, project dashboard statistics.
 - Failure-injection tests for every package transaction: failure midway, disk full,
   kill between stage and replace, concurrent writers, iCloud item not downloaded.
 - Later phases keep these green; golden updates need my approval.

PHASE 1 - VERIFY THE FIXES AND AUDIT CONCURRENCY/ERRORS
 For each item: failing-first test, fix if needed, verify.
 a) Notes: tests that a stale edit raises a visible, retryable conflict (never "saved"),
    a note counts as saved only after reload from durable storage, and it survives
    editor close, tab/project switch, relaunch, scan finalisation, recovery, rename.
 b) Exports: tests for the request identity (project + source + scope + format +
    geometry source + options + locale/units + source revision): selection alone creates
    nothing; same unchanged request reuses; changed source regenerates or saves a
    labelled version; stale async completion ignored; temp/preview files never become
    saved exports; legacy files untouched; filename, extension, content type and bytes
    match. Remove or justify the remaining UUID().ext path.
 c) Concurrency/error audit table: all 87 Task.detached, 135 try?, every @MainActor
    type: file/line, what runs where, owner, cancellation, swallowed error or race risk,
    decision (keep / structured concurrency / propagate / log), status. Fix reproducible
    issues only. Critical save/recovery/import/export/delete failures surface with retry;
    optional cleanup try? may stay.
 d) Race tests: duplicate recording start, duplicate scan finalisation, concurrent writes
    to one package, stale export/project reload, wrong-project assignment, simultaneous
    playbacks, old camera task updating a new scan, save-after-delete, repeated import.
 e) Capture hot-path rules: no JPEG encoding, JSON writing, geometry or file I/O on the
    main thread; no per-frame work in SwiftUI body; ARFrame never retained longer than
    needed; bounded-rate status overlays; no continuous timers/animations over the
    camera; thermal state handled.

PHASE 2 - STORAGE, RECOVERY, CATALOGUE
 - One transaction infrastructure (safe paths, coordinated I/O, staging, atomic
   replacement, backup recovery, interrupted-write handling, corrupt-package detection,
   free-space check, temp cleanup). Move TechnicalRoomPackage onto PackageReplacement/
   SafePackageRead ONLY if its backup-directory recovery stays compatible (legacy fixture
   + simulated interrupted write); otherwise extract shared pieces and document why.
   Never delete recovery data after a failed operation.
 - One authoritative catalogue (rooms, houses, Technik scans, designs, photos, voice,
   notes, exports, unfinished scans) feeding RoomStore, TechnicalRoomLibraryStore,
   RenovationWorkspace and the dashboard: stable IDs, local vs iCloud identity, offline
   items stay visible, targeted invalidation, no duplicate stores for one project/
   location, cached summaries invalidated by source revision (verify the new dashboard
   cache does this).

PHASE 3 - SHARED MEDIA AND ANNOTATION LAYER (consolidate what remains duplicated)
 3a (no capture-engine changes): one photo flow (JPEG off-main, limits, IDs, pose,
   metadata) with thin House/Technik adapters (Technik keeps depth/keyframe evidence);
   one marker descriptor/action set with separate SceneKit/RealityKit adapters; one
   audio recording/save/retry/recovery workflow and one playback coordinator with a
   capture-context policy (RoomPlan audio-session borrowing preserved; one recorder per
   session; one playback at a time; transactional re-record); independent written notes
   with the smallest backward-compatible extension; one thumbnail loader with bounded
   cache. Verify the existing implementations first; merge duplicates; do not add
   parallel versions.
 3b (capture engines, LAST, smallest steps, device checklist): shared capture state
   model and controls over CapturePersistence, ScanSessionStore, CaptureBackgroundFlush,
   LiveScanNotes. RoomPlan and ARKit session management stay separate; behaviour
   unchanged unless a measured bug says otherwise.

PHASE 4 - DETAIL VIEWS, ITEM ACTIONS, PREFERENCES, EXPORT PIPELINE
 - Shared components for RoomDetailView/HouseDetailView; Technik reuses layout and media
   actions, keeps its engineering tools.
 - One set of item operations (rename, edit organisation, move, duplicate, delete,
   import, export, share, open in Studio) for menus, swipe actions, buttons and
   shortcuts; distinguish remove-from-project vs delete package vs delete design/export;
   confirmations on destructive actions.
 - One preference resolver (explicit override > project > app default); opening a project
   never mutates global defaults (verify the new scoping with tests).
 - One export orchestration (scope, options, privacy, filenames, progress, cancellation,
   temp workspace, manifest, checksums, validation, archive, atomic publication,
   catalogue, sharing) over the existing format writers.

PHASE 5 - STUDIO AND GEOMETRY
 - Studio: one editor session as authoritative state; shared commands; split
   StudioEditorView only where it removes real duplication; update only changed parts of
   the scene. Portrait/landscape verified on device.
 - Geometry: keep HouseWallGraph, ResolvedWallGeometry, PolygonUnion, WallJunctions,
   Geometry, Measurements; one authority per repeated calculation (footprints, openings,
   areas, unions, dimensions, duplicate-opening detection, coordinate conversion). Raw,
   resolved and edited geometry stay separate. No new geometry engine; no untested BIM
   compatibility claims.

PHASE 6 - OPTIMISE AGAINST BUDGETS
 - Only what Phase 0A shows to be slow or large: repeated decoding, large buffers,
   retained frames, repeated JSON/package reads, whole-library reloads, full scene
   rebuilds, excess observation, timers, unbounded caches, retain cycles, main-thread
   work. Structured concurrency with clear ownership and cancellation; no blanket
   Task.detached. Before/after numbers from the same tests and dataset.

PHASE 7 - CLEANUP AND FINAL VALIDATION
 - Remove confirmed unused code and unreachable navigation only after replacements are
   verified. Re-run golden, failure-injection, sanitizer, leak, performance, style and
   localisation checks. Update ARCHITECTURE_EN.md and the QA doc. Final verification
   matrix: verified / failed / unverified / device validation pending / needs approval.
 - Device checklist for me: camera, live mic gestures, LiDAR capture, thermal, long
   scans, markers, rotation, interruptions, iCloud.

==================== PART C - REPORT AFTER EVERY PHASE ====================
1. Status (completed/failed/blocked) and scope.
2. Findings and fixes: ID, severity P0-P3, file/line, root cause, fix, test, status,
   evidence.
3. Reuse: code reused, duplicates merged, code removed, production lines added/removed
   (production only; tests/localisation/docs separate).
4. Git: branch, base SHA, new SHAs, PR link.
5. CI: run URL, exact SHA, counts, failures, skipped tests, sanitizer/ratchet results,
   before/after metrics.
6. Unverified (hardware-dependent, infrastructure-blocked, awaiting approval).
7. Risks, assumptions, decisions for me.
8. End with: "Phase N is complete or blocked as documented above. No subsequent phase
   has been started. Awaiting approval."

==================== PART D - ACCEPTANCE ====================
Done when: the whole tree builds and all checks are green on the final commit; one
media/audio/note/marker implementation family serves House and Technik; notes save
independently and reload from disk; one catalogue and one transaction approach (or a
documented reason); exports are explicit, identity-based and not duplicated; detail views
and item actions share logic; Studio and geometry have single authorities; golden,
failure-injection, sanitizer, leak and performance tests pass; budgets met or deviations
explained; device-only items listed for me; existing packages and features work.

Start with Phase G only. Create the branch, run CI, fix what fails, report, STOP.
