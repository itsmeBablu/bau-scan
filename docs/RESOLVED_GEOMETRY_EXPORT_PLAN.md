# Approved export-only geometry companion

User approval: add the companion and preserve all existing formats.

`resolved-geometry.json` is an additional UTF-8 export, with its own schemaVersion
1. It does not replace plan.json/house.json, Technical Room v1 or any native scan
package. Existing importers can ignore this file and retain their old behaviour.

The document includes house identity, per-storey net measurements, room identities,
derived wall centre lines and footprints, thickness provenance, opening host links,
and disjoint floor pieces. Coordinates are right-handed Y-up metres, scoped to a
storey-local datum. A separate storey elevation is null unless scan evidence is
supplied; stacked storeys are never represented as a verified common zero level.
All accuracyMm values are null and capture-derived data is device validation pending.

Derived IDs are deterministic from source wall IDs, story and resolved segment.
Original source IDs remain references. Measured gap, entered thickness and fallback
defaults remain distinguishable. Room net area/perimeter do not change with wall
thickness. Volume estimates use net area times supplied ceiling-height range.

Compatibility/backup: the companion is written into temporary export staging only.
Native packages and existing JSON are not edited; final ZIP publication retains
the previous destination until successful replacement. No scan migration is needed.
Rollback: omit/remove this companion from a generated export; original packages
and legacy importers continue to work. Do not overwrite a source package to add it.

Integration: normal room/house ZIP, organised engineering ZIP and renovation
project source exports. Photos-only/native-backup packages retain their contracts.
Tests cover deterministic re-export, separate unknown storey datums, net room area,
host references, measured/entered/default thickness and explicit null accuracy.
All Apple tests and geometry correctness remain UNVERIFIED until executed.
