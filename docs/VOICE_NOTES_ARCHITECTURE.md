# Voice notes recovery proposal — Phase 4

Status: proposal; persistence integration awaits explicit approval. No voice-note
code has been merged into the quality-review branch. No Apple tests have run.

The local codex/ar-notes branch at c621070 contains an independent implementation
(starting at 6c563f4), including Foundation models, coordinated storage, capture
adapters, iOS AAC recording, playback, local transcription, markers and exports.
It also contains older versions of unrelated capture/export/editor files. Do not
merge that branch wholesale or replace current House Scanner source with it.

## Proposed persistence boundary

Recover the existing Foundation ARNote/ARNoteIndex and storage implementation
selectively, reviewing dependencies and regression tests first. Use a separate
Documents/Projects/<project UUID>/ARNotes/ folder with index-v1.json and bounded
room-specific metadata/audio. Stable note, project and source-reference IDs retain
associations. Text-only notes may have no spatial position. Original scan-local
positions remain distinct from display positions. Keep accuracy null and all
capture-derived positions device validation pending.

No .roomscan, .housescan, .technicalroom, Technical Room v1 or Design Studio
document changes. Old apps ignore the independent folder. An absent folder is an
empty legacy library; corrupt existing notes must fail visibly. No automatic
migration and no deletion of old data. Existing project records are not rewritten
to add notes. Missing source references remain explicit unresolved associations.

Before writing: copy any existing notes folder to a recovery backup. Use
coordinated read/edit/write, validated staging, replacement rollback and bounded
media. Review the recovered branch's backup cleanup and path validation instead
of assuming its old implementation is safe. Limits from that branch are 60-second
clips, 1 MiB per clip and 64 MiB project audio; codec validity requires AVFoundation,
not merely an M4A ftyp header. Synthetic container-header tests are insufficient
to establish playback.

## Integration and backup

Recover in separate commits: pure model/storage tests, independent recorder and
player, optional view integration, then selected export indexes/audio. Do not
change House capture configuration, lifecycle or scan-finalization behavior.
If capture integration needs such changes, stop that part for a separate decision.
Mac reads metadata/audio with Foundation and native playback; iOS recording stays
platform guarded. No ARKit imports in Domain/ or Mac dependencies.

Native scan backups alone do not include this external folder. Export selected
notes separately with IDs, relative paths and checksums, and document restoration
of that folder alongside project data. Restore must validate IDs, paths, limits
and conflicts before replacing data. Do not describe a scan-only backup as a full
project backup with audio.

## Privacy and rollback

No automatic audio upload, Google AI audio request or cloud transcription.
On-device transcription is optional and requires its own capability/consent
review. Recording must work offline without transcription. iCloud, if enabled,
must use the explicitly selected existing storage root; local-only stays local.

Rollback: revert recovery commits; keep the independent ARNotes folder and backup
untouched so a later compatible app can read it. Native scans remain readable.
Never remove user recordings as part of a code rollback.

## Validation gates

Unit tests for IDs, provenance, corrupt/missing audio, coordinated rollback,
association isolation and export integrity; genuine synthetic AAC for Apple audio
tests. Mac/iOS schemes, permissions, microphone, interruptions, playback,
backgrounding, camera coexistence, iCloud and native backup/restore are UNRUN.

Approval requested: the new independent versioned notes sidecar and its backup/
rollback plan. Approval does not authorize native scan-format changes or cloud
audio processing.
