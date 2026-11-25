# Incremental scan persistence — local implementation

Branch: `codex/incremental-scan-persistence`. Baseline: `8d178dd`.
No new dependencies. Existing roomscan, housescan and technicalroom formats remain
readable; optional partial flags and capture timestamps are additive.

## Step commits

- Step 0 — `1cbb682`: audit/checklist, 2 files, +106 / -0 lines.
- Step 1 — `916ba64`: session storage foundation, 3 files, +249 / -0.
- Step 2 — `9feb228`: disk-backed completed House rooms, 6 files, +174 / -21.
- Step 3 — `45d1d9c`: snapshot triggers/lifecycle flush, 6 files, +150 / -10.
- Step 4 — `fd8219e`: changed technical mesh and immediate photos, 4 files, +115 / -12.
- Step 5 — `9568660`: held voice recording, surface notes, media, 9 files, +251 / -29.
- Step 6 — `2b73d99`: unfinished recovery/discard/alignment probe, 10 files, +275 / -0.
- Step 7 — final validation/integration fixes: 24 files, +495 / -97 lines.
  See `git show --stat HEAD` for its commit hash.

Some integration fixes necessarily touch an earlier step's files. The initial
300-line stop boundary was explicitly lifted by the subsequent request to finish
implementation locally. Unrelated skill-file modifications were left untouched.

## Validation evidence

- Initial focused integration: 56 tests, zero failures after fixes.
- Expanded integration/export/capture-presentation run: 67 tests, zero failures.
- Final simulator regression run: 68 tests, zero failures, including the changed-timestamp-origin case.
- Final Mac-target build and signed iPhone-target build both passed.
  A successful build or app launch is not LiDAR validation.

The regression set exercises injected payload/index/manifest failures, backup
recovery, media replacement, session identity, state transitions, orphan cleanup,
partial promotion, idempotence, reference/pose preservation, mesh updates/removal,
changed AR timestamp origins, checkpoint triggers, wall geometry, exports, notes,
photo transforms, bilingual strings, and the full-screen House capture boundary.

An unchanged-anchor test caught unordered JSON hashing; sorted encoding fixed it.
The original X-junction regression now completes. Miter corners restore the outer
wall footprint. The SVG test now counts explicitly identified room-floor elements
rather than mistakenly counting newly introduced wall polygons as floors.

## Operation and limits

- Session drafts live in Application Support/<bundle>/ScanSessions. A shared actor
  serializes app writers. Payloads precede immutable index commit records. Partial
  room slots replace previous snapshots instead of appending duplicate rooms.
- House: Room done writes the room/thumbnail, then Next room reuses the ARSession.
  Finish loads saved native rooms for StructureBuilder. Native USDZ/mesh generation
  is deferred to export into Caches/DeferredCaptureExports, outside source packages.
- Current snapshot defaults: 15 s, 12 geometry items, 512 KiB growth, 3 s minimum
  spacing. Memory/lifecycle triggers can flush sooner. Last encoded bytes, write
  milliseconds, resident memory and thermal state are available in capture state.
  Checkpoint reads have conservative size limits; an oversized draft is retained
  and reported rather than loaded without a bound. Tune thresholds on the device.
- Technik: changed-anchor hashes, removals and frame/event deltas are persisted;
  final compaction produces the existing package. User photos pass retention
  preflight before publication. Automatic evidence has a bounded retained set.
- House JPEGs are read from disk for packaging, not held throughout the scan.
  A stopped voice clip enters the durable outbox and session media. It is not safe
  to assume an in-progress clip survives an OS kill. Disk failures are surfaced.
- Pins are observed surface positions in scan coordinates, not identified MEP
  classifications or accuracy-certified positions. Room/level are saved when
  available; absent values are not invented. New-house native room boundaries and
  surface selection still need physical-device validation.
- Recover promotes a partial package and never overwrites a complete library file.
  A failed promotion keeps the session. Discard names the draft and removes only
  its files; existing library scans and project-note sidecars remain.
- The optional alignment probe is read-only and off by default. Normal tracking
  is only a candidate; no recovered/new-room merge is enabled. A stored Technik
  continuation uses a separate draft revision, preserving its source package.
- Completed session archives are retained locally; they are indexed sessions,
  not an upload queue. No cloud upload or pricing behavior was added.

The suspected finish-memory peak has not been verified as the reported crash
cause. No physical microphone/camera freeze cause was reproduced. CaptureAudio
logs audio-session transitions, and the live HUD avoids a waveform over AR, but
neither change establishes a camera fix. See DEVICE_TEST_CHECKLIST.md before
making reliability, performance, alignment or measurement-accuracy claims.
