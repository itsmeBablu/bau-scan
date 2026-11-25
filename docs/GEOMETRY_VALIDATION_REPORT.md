# Geometry audit — Phase 2 local implementation

Status: implementation recovered and extended; Apple tests and readers UNVERIFIED.
No engineering accuracy or standards compliance is claimed.

## Recovered work and source identity

- Local `feat/phase-1-clean-geometry`: `d14a785`, containing earlier union, graph,
  junction, floor and exporter work. Recovered via cherry-picks with explicit
  conflicts resolved against newer locale/door/slab behaviour.
- Local `feat/technical-room-t1`: `8f042d2`. Current technical-room code is already
  more extensive; it was inspected without replacing models. The legacy branch's
  TechnicalRoom blob differs from current; no wholesale reset/merge was performed.
- Before the user's local-only instruction, remote search confirmed
  `feat/technical-room-t1` existed; `feat/phase-1-clean-geometry` was not returned
  by the exact remote query. No subsequent remote requests were made.

## Changes and invariant coverage

| Area | Change | Regression evidence |
|---|---|---|
| Union | Recovered vertical slab decomposition instead of exponential inclusion/exclusion; non-finite inputs return NaN | Ten-room regression plus deterministic integer-cell oracle and non-finite test, UNRUN |
| Shared walls | Opposing faces, angle/gap/overlap thresholds; explicit side room sets and opening hosts | 2/3/4-room, T/L/X, partial overlap, host and footprint-disjointness tests, UNRUN |
| Thickness | Measured scan gaps or default exterior .365/interior .115; existing nondefault stored thickness retained | Net-area and .4 m override tests, UNRUN; old model does not prove source acquisition |
| Storeys | Graph and floor subtraction are performed separately per storey | Coincident storeys retain eight walls and both floors in a synthetic case, UNRUN |
| 2D/mesh/viewer | Resolved footprints, cut solids, host thickness and disjoint floors consumed by plan, DXF, SVG, OBJ/STL/PLY and ordinary viewer | Updated structural/volume tests; renderer and golden changes UNRUN, not visually reviewed |
| Net dimensions | Room polygons and RoomMeasurements remain source net geometry | Tests assert area unchanged with thickness; no stored format changed |
| JSON companion | Approved additive resolved-geometry.json; null unknown elevations and accuracy; cut solids/host/source links | Deterministic serialization/identity/host/elevation/net-area tests, UNRUN |
| IFC | New resolved mapper uses the same graph and disjoint floor pieces; explicit void/fill relationships and per-storey elevations | Analytical seven-wall two-room test, multi-storey and real-house diagnostics, UNRUN |
| Raw USDZ | Labelled RoomPlan scan (not cleaned), preserved byte assets | Locale audit passes; capture/export runtime UNVERIFIED |

The legacy IFC mapper is retained under `useResolvedArchitecture=false`; the
existing 52-wall real-house oracle is still asserted there. New resolved output
has independent synthetic and graph/quantity assertions. No snapshot values were
invented from unexecuted Swift. The real-house DXF/IFC tests print before/after
counts when run; their actual numbers remain UNVERIFIED, as does proximity to
Apple's historical merged-wall reference of 48.

## Coordinates and limitations

Domain plan is (x,-z); companion maps to right-handed (x,0,-planY) Y-up metres.
IFC uses plan (x,y) as world (x,y,elevation) Z-up, equivalent to room (x,-z,y).
Storey scan elevations are respected when provided. IFC cumulative room-height
fallback remains explicitly estimated; the companion instead records absent
storey elevation as null. Legacy native JSON stays raw and unchanged.

Multi-storey mesh/viewer coordinates still depend on existing per-level export
selection. There is no new persistent building-elevation datum; do not use a
combined multi-storey OBJ as surveyed vertical alignment. Disconnected/invalid
polygons, stair/shaft boundaries, host openings crossing many trimmed pieces and
unusual wall angles require the Mac oracle/reader checks before use.

Thickness source `storedOverrideUnverified` is deliberately not called measured,
entered or manufacturer-supplied in the companion. The internal graph's `.entered`
case identifies the override path only; historical storage has no proof of method.
Default thickness does not alter net room area/perimeter or make hidden geometry
measured. Volume min/max is area times ceiling range, an estimate rather than a
ceiling-surface integration.

Legacy DXF/SVG golden expectations changed with resolved footprints. These are
source changes awaiting execution and review, not approved visual deliverables.
Real Revit, IFC.js, CAD, Preview and model-reader opening was NOT performed.
Optional ifcopenshell validation script exists but no newly generated IFC was
available on this Windows host; no new dependency was installed.

## Verification and compatibility

Local service/localization/plist/diff checks run through
`Scripts/local_quality_baseline.py`; exact commit evidence is under
`.worktrees/phase2-local-evidence.json`. These do not test Swift geometry.
All new geometry and companion/IFC mapper files import Foundation only.
FloorPlan, TechnicalRoom v1 and native room/house/technical packages are unchanged.
The sole approved additive output contract is in RESOLVED_GEOMETRY_EXPORT_PLAN.md.

Phase 2 cannot be marked fully verified: both Apple builds, all new Swift tests,
real-house diagnostics, independent reader checks and device validation are
UNVERIFIED/BLOCKED under local-only Windows execution.
