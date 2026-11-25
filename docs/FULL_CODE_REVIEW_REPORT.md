# Full quality review — Phase 0

Base: `45040ec03dd3316e291ba991667e5457b69a5d90` (`codex/mac-review-fixes`).
Working branch: `codex/full-quality-review`. Only Phase 0 is active.

Objective: establish the actual build/test baseline for both Apple schemes,
strict localization and the Python service. Previous static fixes are not evidence
of compilation or functional correctness. Apple builds are initially UNVERIFIED.

The repository targets iOS 18.0 and macOS 15.0, Swift language mode 5.9 with minimal
strict concurrency. XcodeGen generates RoomScanner and RoomScannerMac with a shared
RoomScanner module. GoogleSignIn is used on both platforms; Sparkle is Mac-only.
The historical architecture overview described only Sparkle; mirrored build-audit
corrections now identify the actual packages without rewriting historical decisions.
No dependency or package format is changed by this baseline audit.

Initial infrastructure: GitHub authenticated repository access is available.
`tests.yml` is absent from the default branch's registered workflow list;
workflow_dispatch returned HTTP 404. The connector PR action returned HTTP 403;
the Git-authenticated fallback stopped during credential acquisition. No PR or CI
run was created. The user then explicitly changed scope to **local changes only**.
No further remote actions are authorized in this phase.

The first audit change adds toolchain, runner, commit and simulator evidence to the
existing CI logs. No screenshots, release artifacts or physical-device results are
claimed in Phase 0. The manual unsigned IPA workflow remains unchanged.

## Phase status: BLOCKED

Scope inspected: both architecture documents, README, project.yml, xcconfig,
target membership, schemes, compiler/deployment settings, existing workflows,
previous review report/checklist, technical-room implementation handoff, tracked
source/test/service inventory and platform/compiler guards. Detailed geometry,
security and Apple UI audits belong to later phases and have not started.

Phase 0 cannot meet all four green-check acceptance criteria on Windows with
remote execution stopped by user instruction. No compiler error or failing Swift
test is claimed fixed without an Apple build log.

| Issue | Severity | Root cause / source | Change or outcome | Verification |
|---|---|---|---|---|
| P0-INFRA-01 | P0 | tests.yml not registered in default-branch workflows | Dispatch attempted: HTTP 404; connector PR: HTTP 403; subsequent fallback stopped before PR creation | Actual API responses; no CI run |
| P0-INFRA-02 | P0 | Windows host has no XcodeGen/xcodebuild/Swift | Local-only runner records Apple schemes BLOCKED and exits nonzero | Runner executed; neither Apple target compiled |
| P0-EVIDENCE-01 | P2 | tests.yml lacked full environment identity | Added Swift/macOS/architecture/commit/destination/simulator logs | Static diff only; workflow execution UNVERIFIED |
| P0-DOC-01 | P3 | ARCHITECTURE_EN.md:3 / ARCHITECTURE.md:3 historical dependency summary disagrees with project.yml packages | Added mirrored corrections; README describes selected CI toolchain rather than claiming old-Xcode support | Configuration/source inspection; compatibility UNVERIFIED |
| P0-LOCAL-01 | P2 | No reproducible local evidence report distinguished static checks from Apple builds | Added Scripts/local_quality_baseline.py, with exact commit, dirty state, output, counts and blocking status | Executed on a clean commit; service/localization/plist/diff checks PASSED; Apple BLOCKED |

## Exact-commit evidence

The first clean local baseline ran on
`898be70f2b40e271561ad8f48dfbac7ba2a6c026`. The same runner is rerun after the final
documentation commit; the exact final SHA and captured outputs are in the local
`.worktrees/phase0-local-evidence.json`. This ignored local artifact is not private
capture data and is not a fabricated GitHub artifact.

| Check | Actual result | Count / limitation |
|---|---|---|
| Python service | PASSED locally | 13 tests, no failures/skips; one Starlette/httpx deprecation warning; mocked provider only |
| Strict localization | PASSED locally | 1,055 entries, zero missing German or unextracted static labels |
| App plist/entitlement/privacy syntax | PASSED locally | Six files; syntax is not a privacy-compliance or entitlement validation |
| Diff whitespace | PASSED locally | No build or runtime inference |
| RoomScanner | BLOCKED / UNVERIFIED | No Xcode, simulator, Swift version, test count or build log available |
| RoomScannerMac | BLOCKED / UNVERIFIED | No Xcode/macOS runner; zero Swift tests executed here |
| GitHub CI | NOT RUN | No run URL, test bundle or downloadable artifact exists |

Host: Windows 11, AMD64, Python 3.14.6. The workflow requests macos-26, but no actual
runner/Xcode/Swift/simulator identity was observed. No screenshots, native exports,
signing, notarization, physical LiDAR, camera, microphone or installation tests ran.

## Git and changed files

Branch: `codex/full-quality-review`; base SHA is recorded above.

- `14a948b360252bc1653ec08423ab3da713228c72` — CI evidence and inventory. This commit
  was pushed before the user stopped remote work; main was not changed.
- `898be70f2b40e271561ad8f48dfbac7ba2a6c026` — local baseline script and build docs.
- Final documentation commit: inspect `git log -1` and the exact local evidence
  artifact. No later commit is pushed.

Changed paths: `.github/workflows/tests.yml`, `Scripts/local_quality_baseline.py`,
`ARCHITECTURE_EN.md`, `ARCHITECTURE.md`, `README.md`,
`docs/FULL_CODE_REVIEW_REPORT.md`, `docs/REVIEW_COVERAGE_MATRIX.md`,
`docs/QA_VALIDATION_REPORT.md`. No app source, format, schema, dependency, privacy
setting, test assertion or capture behaviour changed in Phase 0.

## Local reproduction

Use a Python environment with the existing service development requirements:

```powershell
python Scripts/local_quality_baseline.py --output .worktrees/phase0-local-evidence.json
```

Exit code 1 is expected here because Apple checks are blocked; the script never
pretends the whole baseline is green. It makes no network request or Git mutation.
Pytest and localization results do not validate Swift, UI or physical capture.

Risks: Apple compile errors and failing tests may remain undiscovered; old
architecture claims/results are historical and are not evidence for this commit.
Coverage inventory is not a claim that every file has been reviewed. Later phase
documents and changes are intentionally deferred. No migration is proposed.

Phase 0 is blocked as documented above. No subsequent phase has been started. Awaiting approval.

## Phase 1 local implementation report

Status: local fixes implemented; Apple verification BLOCKED/UNVERIFIED. The user authorized continued local phase work. No remote request, push, merge to main, schema change or dependency change occurred.

| ID | Priority | Root cause / files | Fix / regression | Evidence status |
|---|---|---|---|---|
| P1-PRINT | P1 | PrintController.PDFPageView drew only page 1 | Per-page rectangles/range and ordered drawing; PrintPaginationTests covers one/three pages, invalid numbers and multi-storey PDF | UNVERIFIED; physical printing not tested |
| P1-ZIP | P1 | ArchiveExporter removed destination before copying | Sibling staging, structural validation, manifest size/hash checks, recoverable replacement; failure/cancel/security regression fixtures | UNVERIFIED Swift tests; Mac unzip integrity check included but unrun |
| P1-DXF | P1 | Lossy CP1252 encoding or empty fallback in three export paths | Shared non-lossy codepage encoder with UTF-16 Unicode escapes; German/non-Latin/supplementary-character tests | UNVERIFIED; no CAD reader was opened |
| P1-MAC | P1 | Unsupported selections, swallowed deletion/subject errors, stale async loads | Eligibility checks, native Trash, visible errors, guarded publishing after cancellation/root changes, disabled export options while busy | UNVERIFIED native behaviour; selection regression extended |
| P1-SILENT | P1 | Missing/current error audit, corrupt scan fallback | File/line CSV plus explicit triage; present corrupt scans and failed plan updates now propagate; RoomStore regression | Inventory generated; Swift tests UNVERIFIED |

The current lexical inventory has 81 try? source matches, zero app try!, 73 force-unwrap candidates and zero fatalError/preconditionFailure/TODO/FIXME matches. This excludes tests and is not an AST proof. Remaining candidates are not claimed safe: the CSV records follow-up decisions, with storage/export/capture failures prioritized for later reliability review. In particular, optional photo/render fallbacks and Model I/O replacement remain open audit risks.

Prior fixes 1–23 were rechecked against their changed APIs/test sources: their existing regression files remain present, the synchronous Studio API remains for compatibility, both task sources preserve data formats, and gesture grouping remains at endDrag. None is upgraded to runtime VERIFIED. Full Mac/iOS regression is still required; no assertions were weakened.

Phase 1 commits: 529a6e2 (printing/export), 63f1f27 (Mac state), 27240df (corrupt reads), ec52233 (inventory). Exact files/line statistics are available with git show --stat for each commit. The local baseline runner is rerun after the phase documentation commit. No CI URL, application artifact, screenshot or physical-device evidence exists.
