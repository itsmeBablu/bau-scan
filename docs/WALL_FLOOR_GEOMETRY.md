# Wall thickness and floor reconstruction

RoomPlan surface scans do not establish hidden wall or structural slab thickness from a single visible face. The base 0.10 m wall and 0.05 m floor slab values are display assumptions. Studio previously displayed an 0.08 m slab while exports used 0.05 m; both now share the same presentation default. The ordinary survey viewer still displays the observed floor surface.

## Floor outline corrections

FloorPlanBuilder uses the largest valid captured floor contour, including small valid areas previously discarded by the 0.5 m² threshold. Invalid/degenerate captured contours fall back to chained walls, then wall-only bounds. The floor records whether its boundary came from a captured surface, wall reconstruction or estimated bounds. This is provenance, not a claim of completeness; multiple disconnected contours are not merged into one invented polygon.

Fallback viewer/export floors use architectural floor/wall extents. A loose object outside a room no longer enlarges a fallback slab. Objects-only overlays no longer generate an invented floor underneath furniture. Concave floor triangulation remains supported; degenerate boundaries use a closed wall-bounds rectangle for export.

## Entering independently established thickness

Studio → More → Engineering now lists floors as well as walls and equipment. Select a wall or floor, enter thickness in metres and a measurement/construction-document reference, then Apply entered thickness. These values affect the Studio design copy, 2D plan geometry, 3D scene and relevant exports. They do not rewrite raw scan evidence. Floors use footprint bounding width / display slab thickness / footprint bounding depth; these are envelope dimensions, not floor area. Floor entries support thickness, notes and issues; renovation phasing remains available for walls and editable objects.

Use a visible reveal, independent survey or a referenced construction drawing to establish thickness. Values remain independently entered, not automatically verified. Changing thickness makes previous dimension attestations stale when their dimensions differ. CSV includes construction-thickness source and reference. Save the Studio project to retain overrides.

Raw-backed saved Room/House plans are rebuilt by the existing RoomStore flow when opened. Existing independent Studio project snapshots are preserved; their original captured contours are not silently replaced. Legacy plans without raw evidence retain their saved outlines and are labelled legacy/estimated when provenance is unavailable.

Real-device survey validation remains required. No hidden construction, capacity or engineering accuracy is inferred by these changes.
