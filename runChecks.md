# Mac handoff: verification and remaining consolidation

## Screenshot UI follow-up — 27 November 2026 (new, unverified)

Final window choice: B (frame with sill), superseding A/the native window symbol
for the Windows quantity row. DSWindowFrameIcon is an original scalable SwiftUI
vector with four panes and sill, no downloaded asset/dependency. Check light/dark,
Dynamic Type, row alignment and VoiceOver (the Label supplies “Windows”; the drawing
is decorative). This does not change window symbols in floor plans or scan geometry.

3D canvas follow-up: ViewerView's virtual canvas now uses the existing Surface
token (white in light/high-contrast light, dark in dark mode), replacing the fixed
brand charcoal. The existing light-grey wall material is unchanged. Verify live
Light/Dark/System switching, wall-edge visibility and camera/selection preservation.
AR remains camera-backed and is not given an opaque white overlay. This presentation
change has not been built or visually verified on an Apple device here.

Icon selection follow-up: native names are centralized in DS.Symbol. Apply the
user's A/B choices, with window.vertical.closed replacing the split-rectangle
preview. Quantities shows Doors, Windows and Other openings separately; counts
and export calculations are unchanged. Check waveform for voice, ruler for
measurement (final selection), ellipsis options, clock-arrow restore and icon-only 3D/2D/AR modes.
Validate native symbols and accessible labels on iOS 18+/macOS 15+, including
selected states and narrow/Dynamic Type layouts. Waste allowance has an EN/DE
explanation and still adjusts only flooring/paint estimates, not scan measurements.

Preserve the earlier live-preference/name fixes below. Generate with XcodeGen and
run both full schemes after this follow-up. Run StudioRestoreTests (three cases),
ReportedGeometryRegressionTests (two cases), existing Studio conflict/duplicate/
catalogue tests and the previous live preference/renderer regressions.

Manual checks:
- Quantities: inspect all metrics/icons/units, smaller insets and full-width rows;
  no duplicate expandable House metrics. Technical lines and pins still appear.
- From House and Technik libraries open saved items: the app-level project tab bar
  must disappear on every detail sub-tab and return on back navigation. Test deep
  links, iPad, portrait/landscape and accessibility text sizes.
- 2D: text decrease/percentage/increase, ruler and options centered as individual
  floating controls. Test limits, measurement result/clear and zoom/pan.
- 3D: one floating row for 3D/2D/AR, mic, recenter, measure and options. Narrow or
  accessibility layouts must scroll without clipped/unreachable controls. AR still
  disables the existing non-AR measurement mode. Test Quick Look and visibility.
- Studio: saving updates the same design; its source is not offered as a second
  start-design card. Local/cloud or distinct source kinds must not hide each other.
  Explicit duplicates and recovery conflict copies must not be deleted.
- Restore from scan: confirm/cancel, undo/redo, save/reopen, original source bytes
  unchanged and no second design file. Test House (with radiator survey), Room and
  Technik originals; missing/corrupt source must show an error without losing edits.

Reported angled window wall and absent Flur remain unresolved without actual scan
input. Compare the affected .housescan and an older counterpart against bda846a
(23 November, 15:28:05 +01:00) using the SAME JSON input. FloorPlanBuilder is unchanged
since that version; later partition/wall-resolution stages need comparison. Do not
straighten walls, invent room polygons/areas, change native formats or roll back
capture behavior from screenshots alone. Keep capture-derived results marked
device validation pending. All screenshot UI/Studio changes remain unbuilt here.

## New follow-up to verify — 27 November 2026

The Mac continuation report records passing tests for the prior tree. The subsequent
Windows follow-up based on 2369a53 is NEW and has not been built on Apple platforms.
Generate and run both full schemes again before treating it as verified. New tests:
LivePresentationPreferencesTests (iOS only), RoomNamingTests additions,
ProjectScanSummaryTests additions, SVGExporterTests additions and the paint-order
case in PlanRendererTests. Keep all existing export/golden tests unchanged.

Manual acceptance for this follow-up:
- Open App settings from inside a project. Switch Dark to Light and back, including
  System. The currently open settings/navigation/form must update immediately.
- Switch app English/German while settings remains open. Close it and check current
  tabs, sheets and navigation destinations. Test a project using app defaults and
  one explicitly pinned to German/System: its explicit override must remain.
  Navigation paths and unsaved project details must survive preference changes.
- Check the House and Technik bottom-right plus/options controls on iPhone/iPad:
  24 pt glyphs, 48 pt targets, no clipping or lost labels/actions/Dynamic Type support.
- Reopen yesterday's hallway in both room list and 2D. Blank names show Room/Raum;
  existing Flur/custom names stay unchanged. Available polygon areas remain the
  same; absent/invalid areas show unavailable. Room labels must be enabled in 2D
  options. Test manual room rename, including persistence and reopen.
- Inspect PDF/PNG, SVG and 3D floor textures. Floors render once, labels last;
  later overlapping floor fills must not erase earlier labels/graphics. Review
  visual changes rather than silently approving regenerated golden baselines.

No scan from the reported hallway was supplied in Windows, so its actual missing
geometry/classification is not verified. No hallway, area or staircase geometry
was fabricated. Capture/session behavior and persisted formats remain unchanged.

## Current handoff — 2026-11-26

Publication update: after preparing this handoff, the user explicitly authorized
pushing the consolidation work to `itsmeBablu/bau-scan` main. The snapshot below
describes the pre-publication Windows tree. On Mac, inspect the actual checkout
and verify the latest source/test files are present; do not assume the older HEAD
below is the published tip. A successfully published checkout contains the code
needed for these checks without copying Windows build caches. Separate local
AppTheme/icon/logo edits were excluded from the consolidation publication.
The Mac continuation itself remains local unless the user authorizes remote work.

The user requested that remaining work continue on the Mac. This section and the
prompt below supersede the older verification-only restriction. Work locally;
no pull, push, remote workflow run or dependency update is authorized by this file.

Windows checkout: `C:\Users\kanala\Desktop\color\d-walk-scan`.
Branch: `codex/core-consolidation`. HEAD when handed over:
`014b60eb2f375991da790b6c49e04567c272e9aa`.
The latest work is **not all committed**. HEAD alone, a GitHub download, or copying
only this Markdown file will omit implementations and tests. Transfer the current
working checkout, including new/untracked source, test and documentation files.
Preserve unrelated AppTheme/icon/logo edits. Do not transfer `.env`, credentials,
Windows virtual environments, DerivedData or generated `.worktrees` test outputs.
Git history may be transferred with the checkout; do not overwrite another Mac
checkout or resolve its differences by reset/clean. Compare first and preserve both.

No XcodeGen generation, Apple compilation, Swift test, simulator/device validation
or performance measurement was performed for these changes on Windows. Ten Node
checks, localization, style and whitespace passed in the latest local pass. Earlier
Python tooling tests passed; the full backend suite stalled on Windows, while its
11 non-HTTP tests passed with two HTTP tests deselected. Run the full suite on Mac.
Historical results are not evidence for a different checkout or later fixes.

## Prompt to paste into Codex on the Mac

Read `runChecks.md` in this repository, verify the Windows consolidation work,
then continue the unfinished consolidation locally on this Mac. First read
`ARCHITECTURE_EN.md`, `docs/CORE_REFACTOR_PLAN.md`,
`docs/QA_VALIDATION_REPORT.md`, `docs/DEVICE_TEST_CHECKLIST.md`,
`.github/workflows/tests.yml`, and any applicable
`AGENTS.md`. Preserve all existing changes. Do not pull, push, reset, clean, switch
branches, or update dependencies. Inspect the current branch, commit, and dirty
diff before running anything. The Windows handoff used branch
`codex/core-consolidation`, based on
`015dbdb81e57d74fa959348162cca7f95cae70e5`. Verify the actual checkout rather than
assuming it matches. If it differs, report the difference and test that checkout;
do not overwrite it. This Markdown file may need to be copied to the Mac manually:
it has not been pushed.

Run XcodeGen and BOTH full test schemes (`RoomScanner` on an installed iPhone
simulator, and `RoomScannerMac` on macOS). Run the existing localization, style,
Node regression, Python service, plist, and whitespace checks. Keep full logs,
exit codes, `.xcresult` bundles, toolchain versions, simulator identity, commit,
and dirty diff in an ignored `.worktrees/mac-checks/<timestamp>/` folder.
Do not print `.env`, signing credentials, API keys, or local secret configuration.

First fix demonstrated compilation/regression failures, preserving feature behavior.
After both schemes pass, continue the remaining work listed below in small,
testable parts. Give a short report after each part: findings, changed files,
production/test lines, checks actually run and remaining limitations. Do not
weaken tests or add unrelated features/redesign. Re-run both schemes and affected
checks after final changes. Stop the affected change if it would alter persistent
formats, capture behavior or dependencies, or require destructive recovery; explain
the blocker and continue independent authorized work. Never delete real recovery data.

Keep House Scanner behavior and `.roomscan`, `.housescan`, `.technicalroom`, and
Technical Room v1 formats unchanged. New domain logic must remain Foundation-only.
Never invent accuracy or compliance claims; preserve null accuracy. All
capture-derived behavior remains **device validation pending**.

Report each check as passed, failed, blocked, or unrun with evidence. Separate
simulator/macOS tests from physical-device validation. Do not call local Mac tests
GitHub CI, and do not mark the original consolidation CI gate complete without a
successful CI run at the exact final commit. End with a short report and paths to
the logs. Work through the remaining authorized parts until completed or blocked;
do not label the whole consolidation finished while required evidence is missing.

## Remaining work, in execution order

1. **Establish the actual Mac baseline.** Inspect tracked/untracked changes and
   toolchain, generate with XcodeGen, run both full schemes and all local checks.
   Fix demonstrated failures before further refactoring. Inspect `project.yml` so
   new shared test files are included in both test targets and iOS-only capture
   tests remain excluded from Mac. Retain logs before and after fixes.
2. **Complete the concurrency/error review.** Regenerate the source inventory;
   review each relevant detached task, optional try and main-actor operation for
   ownership, lifetime, cancellation, error presentation and late-result identity.
   Record an explicit decision per site; a lexical report is not a completed audit.
   Prioritize asynchronous duplication/root changes in RenovationWorkspace,
   written-note mutation lifetime, Mac import/design refresh callers and remaining
   saved-item/export entry points. Preserve intentional durable writes that finish
   after navigation. Add regression tests for demonstrated risks, not mirrored code.
3. **Finish shared action/media contracts.** Check Room/House/Technik/Studio rename,
   duplicate, delete, export, photo selection and note save/recovery across all
   entry points. Preserve full identity including source kind and local/iCloud root.
   Reuse existing authorities. Keep native deletion/trash and project-label semantics
   distinct when their contracts differ. Recorder/raw-frame adapters and Phase 3b
   remain unvalidated: do not merge the independent capture engines or change AR,
   RoomPlan or audio-session policy as routine consolidation.
4. **Review export baselines.** Execute structural/deterministic/round-trip tests
   and generate representative PDF/PNG, DXF/SVG, OBJ/STL/PLY, JSON/resolved geometry,
   IFC, raw USDZ-copy and ZIP outputs from existing fixtures. Review full output and
   visual golden gaps. Never silently regenerate an existing baseline to accept a
   regression; present changed/new golden artifacts for review. Verify room heights,
   hosted windows, PDF-photo toggle, floor/room photo folders, numbering and no
   duplicate renamed exports. Revit interoperability remains unverified until opened.
5. **Exercise recovery and lifecycle.** Run rollback, stage/publication failure,
   legacy package, dual-backup, note/outbox and checkpoint tests. Use disposable
   isolated fixtures for real process-kill/disk-full experiments; injected errors
   do not prove them. Verify offline/iCloud state and ambiguous backups on suitable
   environments. Never erase or auto-resolve real recovery copies.
6. **Measure before optimizing.** Run the existing synthetic workloads, warning/
   coverage reporting, sanitizers and lifecycle/leak checks. Record dataset, toolchain,
   hardware, exact tested tree and baseline. Set budgets from measured/reviewed data;
   optimize only demonstrated bottlenecks and compare the same workload afterwards.
   Verify Studio incremental-update fallback, camera/floor preservation, portrait/
   landscape and large photo libraries. Do not claim improved performance from LOC.
7. **Physical-device validation.** Use `docs/DEVICE_TEST_CHECKLIST.md` on iPhone
   14 Pro where available: separate House/Technik sessions, long scans, checkpoints,
   background/foreground, interruption/relocalisation, photos, recording/playback,
   reopening saved data, markers and exports. If no device is available, leave
   these pending and complete independent Mac work. No invented accuracy/DIN claims.
8. **Final cleanup and report.** Remove only proven dead/duplicate code after
   verification, preserve unrelated changes and formats, rerun both schemes and
   affected checks, and update the plan/QA report. List completed, failed, blocked,
   unrun and device-pending items separately. GitHub CI stays unverified without an
   actual successful final-commit run; do not push or trigger it without authorization.

All steps above are unfinished acceptance work, not a statement that each needs
new production code. Stop speculative refactoring when evidence supports keeping
an existing implementation. Preserve the latest Windows fixes, detailed below.

## Execution notes

- Use full Xcode, not only Command Line Tools. Record `xcode-select -p`,
  `xcodebuild -version`, `swift --version`, `sw_vers`, and `uname -m`.
- Minimum deployment targets are iOS 18 and macOS 15. Inspect current source and
  installed SDKs to determine whether the selected Xcode supports everything used.
  CI currently uses `macos-26`; do not assume an older Xcode is sufficient.
- If XcodeGen, a suitable simulator runtime, Node, or Python is missing, report it
  before installing tools or changing the selected developer directory.
- Existing Swift packages may need network access to resolve. Keep their versions
  intact and report blocked resolution separately from compiler failures.
- Run checks independently so an iOS failure does not hide the macOS result.
- `Scripts/test.sh` filters output. Use direct `xcodebuild` commands for full logs.

## Reference commands (Bash, from the repository root)

Run this block in Bash, or translate it carefully for the active shell. Do not use
`set -e`: each test result must be recorded even if another test fails.

```bash
set -uo pipefail
CHECK_DIR="$PWD/.worktrees/mac-checks/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$CHECK_DIR"

run_check() {
  local label="$1"
  shift
  "$@" 2>&1 | tee "$CHECK_DIR/$label.log"
  local result=${PIPESTATUS[0]}
  printf '%s\t%s\n' "$label" "$result" >> "$CHECK_DIR/exit-codes.tsv"
  return "$result"
}

git rev-parse HEAD > "$CHECK_DIR/commit.txt"
git branch --show-current > "$CHECK_DIR/branch.txt"
git status --short > "$CHECK_DIR/status-before.txt"
# Inspect filenames first. Do not save diffs containing local secrets.
git diff --stat > "$CHECK_DIR/diff-stat-before.txt"
run_check developer-directory xcode-select -p
run_check xcode-version xcodebuild -version
run_check swift-version swift --version
run_check macos-version sw_vers
run_check architecture uname -m
run_check xcodegen-version xcodegen --version
run_check generate xcodegen generate
```

If generation fails, retain its full log and address that failure before testing
the generated project. After successful generation, select an available simulator:

```bash
xcrun simctl list devices available -j > "$CHECK_DIR/simulators.json"
SIMULATOR_ID="$(python3 - "$CHECK_DIR/simulators.json" <<'PY'
import json, sys
with open(sys.argv[1]) as stream:
    devices = json.load(stream)['devices']
phones = [device for runtime, group in devices.items() if '.iOS-' in runtime
          for device in group if device.get('isAvailable')
          and device['name'].startswith('iPhone')]
if not phones:
    raise SystemExit('No available iPhone simulator; install a supported runtime.')
print(phones[0]['udid'])
PY
)"

# Run iOS only if simulator selection succeeded and SIMULATOR_ID is nonempty.
if [ -n "$SIMULATOR_ID" ]; then
  printf '%s\n' "$SIMULATOR_ID" > "$CHECK_DIR/selected-simulator.txt"
  run_check ios-tests xcodebuild -project RoomScanner.xcodeproj \
    -scheme RoomScanner -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
    -derivedDataPath "$CHECK_DIR/DerivedData-iOS" \
    -resultBundlePath "$CHECK_DIR/RoomScanner.xcresult" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test
fi

run_check mac-tests xcodebuild -project RoomScanner.xcodeproj \
  -scheme RoomScannerMac -destination 'platform=macOS' \
  -derivedDataPath "$CHECK_DIR/DerivedData-Mac" \
  -resultBundlePath "$CHECK_DIR/RoomScannerMac.xcresult" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test

run_check localization node Scripts/audit_localization.js --strict
run_check json-regressions node --test Scripts/test_json_unique_keys.js
run_check ui-design-regressions node --test Scripts/test_ui_phase0.js Scripts/test_design_system.js
run_check styles bash Scripts/audit_styles.sh
run_check whitespace git diff --check
```

Use a Python virtual environment under `.worktrees/` for the existing service test
dependencies; do not install packages into system Python. Installing the pinned
development requirements below does not add a runtime dependency to the app:

```bash
python3 -m venv "$CHECK_DIR/python-env"
CHECK_PYTHON="$CHECK_DIR/python-env/bin/python"
run_check service-test-setup "$CHECK_PYTHON" -m pip install \
  -r services/technical-google-ai/requirements-dev.txt
run_check service-tests "$CHECK_PYTHON" -m pytest services/technical-google-ai -q
run_check local-baseline "$CHECK_PYTHON" Scripts/local_quality_baseline.py \
  --output "$CHECK_DIR/local-baseline.json"
git status --short > "$CHECK_DIR/status-after.txt"
git diff --stat > "$CHECK_DIR/diff-stat-after.txt"
git diff --numstat > "$CHECK_DIR/lines-after.tsv"
```

The baseline script intentionally returns nonzero on Mac because its
`Apple-schemes` entry is `UNVERIFIED`: it does not run Xcode itself. Evaluate its
individual checks and attach the separate Xcode results; do not alter the script
to manufacture a pass. If setup fails, mark dependent service checks blocked.
For re-runs, create a fresh timestamped directory so result bundles never collide.

## Results to return to the Windows chat

Write a short `REPORT.md` inside the check directory with:

1. Actual branch, exact commit, and whether tracked/untracked changes were tested.
2. Xcode, Swift, macOS, architecture, simulator name/runtime/UDID, and XcodeGen.
3. Both schemes' exit codes, test counts, failures/skips, and full log paths.
4. Other checks' results, fixes with file references, and added/removed lines.
5. Remaining blockers, warnings, and physical-device checks still pending.

Return `REPORT.md`, `exit-codes.tsv`, `generate.log`, `ios-tests.log`,
`mac-tests.log`, `local-baseline.json`, and failing ancillary logs. Keep the
`.xcresult` bundles available if detailed investigation is needed. Review logs for
secrets before sharing; do not include the virtual environment or DerivedData.

No Apple build, simulator test, physical-device validation, or performance
measurement was performed on Windows for this handoff. This file is a plan,
not evidence that any of those checks passed.

## Latest local additions to verify

The approved local pass also added height min/max columns to quantities CSV;
host-centred window symbols in PDF/PNG/SVG/DXF; the PDF photo preference and
appendix; and six Studio tile presets plus wall-aligned wood. Execute
`ProjectReportTests`, `PDFPhotoAppendixTests`, `PlanOpeningPlacementTests`,
`FloorPatternDirectionTests` and all existing exporter/Studio tests in both schemes.
Check that the capture-persistence lifecycle test is iOS-only. See the dated
`docs/QA_VALIDATION_REPORT.md` entries for exact limits and outstanding work.
Do not overwrite unrelated branding/icon changes if the Mac checkout includes them.

The later consolidation also shares thumbnail/image processing, uses lazy House
photo references, shares Room/House controls and patches object-only Studio edits.
Run `PhotoThumbnailCacheTests`, `PhotoImageProcessorTests`, `CoreLifecycleTests`,
`ProjectEvidenceSummaryTests`, and the complete `SceneStudioTests`. Review the
guarded full-scene fallback and actual floor/camera/unaffected-node preservation.
Manually verify photo orientation, large galleries, rapid photo selection/closing,
Room/House toolbar shortcuts, rename-error alerts and Studio add/move/delete/undo.
Inactive recorder lifecycle tests must never request microphone permission.

Also run `python3 Scripts/test_local_quality_baseline.py` for the runner's own two
evidence-handling tests. The baseline tool now supports `--timeout SECONDS` (default
120 per subprocess) and saves partial progress. Windows' latest bounded backend
check timed out at 30 seconds; investigate the actual backend on Mac and attach
its full result. Do not interpret passing runner unit tests as a backend pass.

Run `python3 Scripts/test_swift_concurrency_audit.py` and regenerate the source
inventory with `python3 Scripts/audit_swift_concurrency.py --output
.worktrees/core-concurrency-mac.json` (one shell line). This masks comments/literals
and preserves locations, with documented interpolation/regex limitations. Sites
marked `review-required` are not an exhaustive completed concurrency review.

New saved-view work: run `SavedScanEvidenceTests` and `LibraryItemOperationTests`.
Verify 2D/3D markers still open the correct photo, the camera button preserves its
pose behavior, gallery sheets retain their compact style where previously used,
and independent corrupt-note/photo cases leave the other evidence visible. Full
JPEGs should only be opened for gallery pages, not to populate marker metadata.

Also run `PackageTransactionBoundaryTests` and the added technical staging-failure
case. They inject stage-creation errors and compare every pre-existing package file,
including nested room/raw evidence, before checking retry. They do not simulate a
real full disk or killed process. Full test schemes must retain all prior tests.

Latest Windows backend diagnosis: pytest collected all 13 cases but stalled on the
first TestClient HTTP case during asyncio Windows event-loop socketpair creation;
the faulthandler stack reached `socket.accept` before endpoint logic. Do not change
or skip backend assertions to manufacture green results. The updated baseline
runner emits thread stacks before its deadline; return them if Mac also stalls.

Run `SavedFileRevisionTests` and the evidence-summary test for atomic replacement
with unchanged byte count/timestamp. Check that inode/file identity changes are
observed and stale previews are not returned. These checks share the same metadata
reader with thumbnail caches and export hashing; retain all their regression suites.

Run `python3 Scripts/test_compiler_warning_report.py` (three tooling tests).
The manual diagnostics workflow now extracts coverage JSON and independently
records/enforces supplied Swift and all-build warning ceilings. Leave ceilings
blank for the first measured baseline; do not choose an invented budget. Local
warning reporting can be run on the captured compiler logs using
`python3 Scripts/compiler_warning_report.py --log <tests.log> --output <warnings.json>`.

Run `NoteSaveWorkerTests`, `NoteTransactionRaceTests`, and the added superseded-audio
case in `VoiceNoteRecoveryTests`. Verify actual destination bytes before a success
message/outbox removal, stale edit conflicts, two concurrent text editors, concurrent
text/audio saves, failed-save retries and recovery limited to one new note ID.
An older unapplied recording must stay in the outbox when a newer recording exists.
Live notes use the same durable-write boundary; microphone/AR session policies must
remain unchanged during House and Technik device tests. Durable writes are not
cancelled merely because the editor closes; pending failure state must remain clear.

Diagnostic Windows subset: 11 non-HTTP backend tests passed, with the two HTTP
tests deselected. This does not replace the required full 13-test suite. Run the
full suite on Mac; preserve the HTTP authentication/contract assertions unchanged.

Run the new dual-copy backup cases in `PackageReplacementTests` / `ARNoteTests`,
the conservative orphan-cleanup case in `ScanSessionStoreTests`, and the iOS
completion test in `CoreLifecycleTests`. If current and recovery files coexist,
both must remain and saving must report an explicit conflict. Missing-target
recovery must still work. Repeated checkpoint completion must be idempotent and
a failed finalizing write must not advance to completed. Use disposable fixtures;
never delete real recovery data just to pass the checks.

Run `ArtifactPublicationBoundaryTests` plus all existing artifact-reuse, saved-file,
export-service and ZIP tests. Failure before/after staging or before the index must
keep old exports and their index associations; reused bytes must never be removed
on an index error. Changed source during copying must fail checksum validation.
Validate cancellation and normal retry with the same destination folder. Reuse now
also rechecks source/request identity before returning; measure its cost on Mac.

Some image/lifecycle/documentation edits may be uncommitted because local commit
approval failed at the approval service's usage limit. Inspect the actual working
tree rather than assuming HEAD contains those changes. Do not bypass approvals
or include separate branding edits in a consolidation commit without authorization.

Run the three additional SavedExportFilesTests covering cancelled reuse, source
replacement after hashing and copy failure/cancellation with retry. Verify prior
exports remain and no staging file remains under normal filesystem conditions.
These Swift tests were written on Windows and have not been run. Measure the
revision-check overhead on Mac; no performance improvement is claimed.

Run ExportChecksumTests including the independent multi-chunk reference vector,
1 MiB boundary cases, pre-cancellation and missing-file retry. These tests remain
unrun on Windows. The implementation still uses 1 MiB reads; assess actual memory,
throughput and cancellation latency on Mac without inferring them from source.

Run ProjectArtifactLibraryTests including rename/delete rollback with a corrupt
index and retry after restoring that disposable fixture. Run OperationLifetimeTests.
Manually delay a rename/delete, trigger catalogue refresh or navigate away/back,
and verify generation cancellation cannot enable another action while the edit
is running. Verify late errors do not appear on a closed/different project and
the generated-file share link is cleared after a successful rename/delete.
This UI behavior and the added Swift test have not been verified on Windows.

Run StudioConflictTests: wrong existing destination source/type or ID must reject
before overwrite or conflict-copy creation, regardless of matching/stale revision.
Keep the existing legacy and genuine same-source stale-writer recovery tests green.
This added destination-identity test remains unrun on Windows.

Mac design catalogue: delay a load, start a second refresh, and verify the older
result/error cannot replace the newer request. Repeat across primary and secondary
storage-root changes and window disappearance. Verify cancellation produces no
error alert, current corrupt-design errors remain visible, and root precedence is
unchanged. With over 200 disposable design files, verify a repeatable sorted subset;
the existing 200-per-root limit remains. This Mac UI change is unverified here.

Run WorkspaceReloadTests on both schemes. A project note saved while catalogue
refresh is suspended must remain current in memory and on disk. Cancellation at
the publication boundary must leave the original index bytes, notes root and
catalogue revision unchanged without an error alert. Tests use an injected local
root and a checkpoint; they must not modify real Documents or global root defaults.
Manually verify queued refreshes and local/iCloud root changes, including failure:
mutations remain blocked until the new catalogue is published. All remain unverified
on this Windows host.

Run StudioConflictTests and WorkspaceReloadTests additions for duplication and
removal. Duplicating an already saved room/house/technical Studio design must start
at revision 1 at the intended new source ID, preserve original bytes and allow an
independent revision 2 edit. Removal completion must preserve an intervening project
note in memory and on disk. Retain ProjectScanRemovalTests for dependencies, stale
catalogues and retained trash. Manually test root switches during these operations;
the broader asynchronous duplication/root-switch review remains outstanding.
