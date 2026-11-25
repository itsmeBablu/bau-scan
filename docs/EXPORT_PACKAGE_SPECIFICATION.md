# Organized export contract

Phase 3 local implementation. Apple builds, archive extraction and restore tests
are UNRUN. This is an export contract, not a native storage migration.

The existing plans/, models/, studio/, photos/ and single technical-room/ paths
are preserved. Multiple explicitly selected surveys use technical-rooms/<name>-<id>/.
See ORGANISED_EXPORT_REVIEW.md for photo indexes, associations and privacy.

Presets configure available selections: Complete Project, Engineering / BIM
Package, Technical Room Package, Floor Plans Only, 3D Models Only, Photos Only,
Native Backup and Custom Export. Presets preserve explicit technical IDs, locale
and units; they do not select an unrelated survey automatically. Custom controls
remain available. Complete Project requires a real source package for its backup;
a generated/manual plan without one must use another preset or disable backups.

Optional bim/architecture.ifc contains the house architecture. Technical IFCs are
separate UUID-named files in independent room frames. Explicit survey selection
is not verified registration, so this exporter never invents shell-to-house
placement to create a combined IFC. The existing registered IFC API is retained.

Optional native/<UUID>.roomscan, .housescan and .technicalroom directories are
coordinated, byte-preserving snapshots of selected source packages. Every regular
file is included in the outer manifest with a size and SHA-256. Original package
formats remain unchanged. Import the extracted package through its existing import
path. Design Studio JSON remains separate; a source backup is not an automatic
full-project restore of all independent libraries. External ARNotes are not yet
included. No new automatic restore/import format is introduced.

Native backups preserve source metadata, including original photos. Metadata
removal is disabled for native backups; the service rejects incompatible options
rather than producing a falsely sanitized backup. JPEG-copy privacy still applies
to selected derived photo exports when native backups are disabled.

Verification written: preset selection/identity tests and synthetic room native
snapshot -> read -> hash/plan/ID comparison. Tests are UNRUN. Standard ZIP reader,
complete native reimport, IFC readers and device capture validation remain pending.
Granular floor/room selection, reliable counts/size estimates, complete per-format
reader validation and generated CI example archives remain open. No remote run,
artifact, migration, signing or engineering accuracy is claimed.
