# Storage/recovery — Phase 6 local checkpoint

Reviewed coordinated native snapshots, archive manifest validation, the independent
notes store and its local delivery outbox. Existing room/house/technical package
formats and scan capture code are untouched. This is not a full iCloud audit.

P1-MANIFEST: inventory checks loaded each asset into Data, including large meshes,
and accepted Boolean/fractional byte counts. They now preflight the directory,
inspect regular-file sizes and stream hashes; malformed inventory types, duplicate
canonical paths, empty path components and invalid checksum types fail explicitly.
Legacy project manifests without items retain their separate contract. Inventory
checks validate listed files; they do not prove semantic correctness of each format.
PhaseOneExportSafetyTests adds malformed inventories and invalid-size cases; UNRUN.

Notes storage uses independent coordinated replacement and recovery, with bounded
metadata/audio, symlink rejection below the library root and explicit corruption
errors. Completed recordings first enter a local outbox, then the selected library;
outbox deletion follows destination success. Unresolved references remain pending.
VoiceNoteRecoveryTests covers idempotent delivery and unrelated reference isolation;
UNRUN. App termination during an unfinished recording remains an open risk.

NativeExportSnapshot preserves package bytes and IDs. Its synthetic read/hash
comparison is written but UNRUN. Full restore through RoomStore/import, linked
Design Studio data, external audio restoration and live iCloud conflicts are open.
No automatic migration or new restore format was added.

Remaining: full cloud switching/conflict/concurrent-write stress, resource profiling,
all scanner lifecycle/device checks, multi-window saves, unlisted source attachment
audits and complete import/decompression testing. Both Apple schemes remain BLOCKED
on Windows. No performance, storage-integrity or capture-wide verification is claimed.
