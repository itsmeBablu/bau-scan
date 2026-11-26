# Mac handoff: build and regression checks

## Prompt to paste into Codex on the Mac

Read `runChecks.md` in this repository and execute its verification plan locally.
First read `ARCHITECTURE_EN.md`, `.github/workflows/tests.yml`, and any applicable
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

Fix only small, demonstrated compilation or regression failures needed to make
these checks pass, preserving feature behavior. Do not begin additional consolidation,
redesign, performance refactoring, or new features. Local implementation after this
handoff was explicitly approved with Mac verification deferred; inspect and test
those changes too. Do not weaken tests. Re-run
both schemes and affected checks after the final fix. Record changed files and
added/removed lines. Stop if a fix would change persistent formats, capture
behavior, dependencies, or require destructive recovery; explain the blocker.

Keep House Scanner behavior and `.roomscan`, `.housescan`, `.technicalroom`, and
Technical Room v1 formats unchanged. New domain logic must remain Foundation-only.
Never invent accuracy or compliance claims; preserve null accuracy. All
capture-derived behavior remains **device validation pending**.

Report each check as passed, failed, blocked, or unrun with evidence. Separate
simulator/macOS tests from physical-device validation. Do not call local Mac tests
GitHub CI, and do not mark the original consolidation CI gate complete without a
successful CI run at the exact final commit. End with a short report and paths to
the logs so I can return the results to the Windows chat. Do not start later phases.

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
