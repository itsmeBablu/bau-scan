# Full quality review — Phase 0

Base: `45040ec03dd3316e291ba991667e5457b69a5d90` (`codex/mac-review-fixes`).
Working branch: `codex/full-quality-review`. Only Phase 0 is active.

Objective: establish the actual build/test baseline for both Apple schemes,
strict localization and the Python service. Previous static fixes are not evidence
of compilation or functional correctness. Apple builds are initially UNVERIFIED.

The repository targets iOS 18.0 and macOS 15.0, Swift language mode 5.9 with minimal
strict concurrency. XcodeGen generates RoomScanner and RoomScannerMac with a shared
RoomScanner module. GoogleSignIn is used on both platforms; Sparkle is Mac-only.
Existing architecture prose describes only Sparkle and is stale on dependencies.
No dependency or package format is changed by this baseline audit.

Initial infrastructure: GitHub authenticated repository access is available.
`tests.yml` is absent from the default branch's registered workflow list;
workflow_dispatch returned HTTP 404. Use the authorized PR CI fallback against
`codex/mac-review-fixes`, without merging or modifying main.

The first audit change adds toolchain, runner, commit and simulator evidence to the
existing CI logs. No screenshots, release artifacts or physical-device results are
claimed in Phase 0. The manual unsigned IPA workflow remains unchanged.
