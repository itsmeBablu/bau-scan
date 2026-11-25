# Voice notes recovery proposal — Phase 4

Status: independent storage approved by the user on 2026-11-25. Selected model,
storage, recording and playback source is now recovered on the quality-review
branch. No Apple tests have run.

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

## Local implementation checkpoint

Recovered ARNote, recording/transcript policies, ARNoteStore and regression tests
selectively. Added optional title metadata within the approved new notes format.
Hardened notes directory limits and symlink checks. Existing architectural
ProjectPin is unchanged: technical notes do not become architectural pins.

Projects now expose a separate Voice notes screen: explicit scan association,
iOS record/pause/resume/stop with first-use confirmation, elapsed time, retry after
a failed save, title/description editing, confirmed deletion, playback and seeking.
Mac can read/edit/play; Mac microphone recording is not implemented. Permission
descriptions are EN/DE. UI operations use detached storage tasks. No existing scan
coordinator, ARSession, source package or House capture view is modified.

Optional standalone voice-note ZIP export includes selected project/source notes,
CSV/JSON indexes, text, hashes and optional M4A. Audio inclusion defaults off.
Transcripts are excluded. Missing or unrelated source references are not silently
exported. This is not yet integrated into every organized export/native backup.

All Swift/audio/UI tests are UNRUN. Added a genuine synthetic AAC generation test
for Apple hosts; older ftyp-header tests remain storage-structure tests only.
Outstanding: live AR markers, per-equipment association controls, background/crash
recovery for an unfinished clip, transcription UI, combined archives, audio-aware
native restore, and complete hardware validation. Completed clips are staged in a
local Application Support/VoiceNoteRecovery outbox using the approved ARNote
format before delivery to the selected library. The outbox remains until the
destination transaction succeeds; recovery uses stable IDs and explicit source
references. Back/dismiss controls are guarded while recording/saving or when a clip
could not be staged. If both stores reject writes, only in-memory retry remains;
never claim crash recovery for that condition or for an unfinished clip killed by
the OS.
No phase-completion, full backup or microphone behavior is claimed.

## Direct AR entry and simpler controls

Saved House and Room viewers expose Voice note alongside Reset and Options in 3D,
2D and AR. Options groups object/dimension visibility, virtual-view measuring,
Quick Look and AR scale; virtual point measuring is not offered in camera AR.
The direct notes sheet preselects the scan and reuses its existing project owner.
Unassigned scans use Unsorted without moving references from another project.
Library identity remains part of the association, so local/iCloud items with the
same UUID are not conflated. Recording uses one explicit Record action, system microphone
permission, pause/stop, durable recovery and local-only storage. A repeated
confirmation dialog is no longer inserted before every recording. These are
scan-linked audio notes, not spatial AR pins or automatic transcription.

Utility-room capture has a microphone beside its mesh/tools controls. Its notes
use the capture's eventual scan UUID. Save that scan to retain the geometry
association; cancelling capture does not delete already saved audio. Detailed
capture counters are inside the tools area. Opening notes does not configure or
replace an ARSession.

The app's permanent project/scan accessory above the tab bar is removed. Project
selection belongs to New Scan. The launch screen is a project list; each project
contains House, Technik and Studio tabs. Capture starts in that project. Existing
standalone room scans remain readable, but new capture offers House and Technik
only. House capture notes use a stable UUID assigned to the saved house package.
Cancelled capture retains already saved audio and its reference.

Studio uses an edge-to-edge viewport with floating controls. Selecting a survey
photo opens an in-canvas panel (side panel in landscape, lower panel in portrait),
so the photo and 3D scene remain visible together. Photos fit both viewport axes.

Package destinations explicitly reload their RoomStore before resolving records;
an unloaded catalogue must not be treated as a missing package.
