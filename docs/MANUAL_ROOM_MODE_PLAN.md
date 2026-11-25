# Phase 9 — manual room mode (design only)

No manual capture is implemented in this phase. Non-LiDAR users can open imported
scans, saved designs and project notes. Unsupported capture must say why it is
unavailable, with a clear route back to projects; do not present a non-working scan button.

## Recommended first implementation

Use a native 2D sketch with entered lengths before AR corner tapping. A sketch
works without camera/depth support, is easier to correct, and makes its assumptions
visible. Create a separate project-side manual-plan document, not synthetic
RoomPlan evidence. Agree its schema separately before implementation.

1. Pick a project, create a named room and enter floor elevation and ceiling height.
2. Draw a closed polygon; snap to axes optionally. Enter reference lengths and
   mark every dimension entered/estimated, with method and unknown uncertainty.
3. Reject self-intersecting/zero-area polygons; show open endpoints and conflicting
   dimensions. Undo/redo preserves the original sketch operations.
4. Add openings and their wall hosts, sill heights and dimensions explicitly.
5. Preview floor plan and derived 3D boxes, clearly labelled manual model.
6. Export a manual-model report with all assumptions. Never label it a LiDAR scan.

## Optional later AR aid

On devices with world tracking, tap estimated horizontal-plane intersections and
enter measured wall lengths. Depth/mesh must not be assumed. Require a known-distance
check and alignment checkpoints after interruptions. Estimated AR points cannot
silently replace entered dimensions. Occluded corners require manual specification.

## Scope and acceptance

One floor, polygonal rooms, simple openings and user-entered heights initially.
No automatic recognition, hidden construction inference or claimed scanner accuracy.
Test polygon validity, dimensional constraints, closure, unit conversion, revisions,
round-trip persistence and exports. Device checks cover camera permissions, absent
planes, tracking loss, accessibility, landscape and interruptions.

Device validation pending. No delivery estimate is implied by this plan.
