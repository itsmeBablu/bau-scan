# Mesh retention and architectural display

Technik capture uses its own ARKit mesh session, independently of House RoomPlan. New captures retain bounded latest-per-anchor geometry across sampled frames, so a final frame with fewer mesh anchors does not silently discard previously observed equipment. The cache keeps at most 250,000 vertices and replaces an updated anchor rather than layering its old triangles over the new version.

Plane detection is disabled for this session to avoid flattening shallow equipment into architectural planes. This changes newly scanned geometry only. The live camera has a Show captured mesh switch; mesh capture itself is independent of the display switch.

New snapshots preserve ARKit's per-face classification where available. In the saved viewer, Room surfaces hides classified walls, floors, ceilings, doors and windows. Unknown faces remain visible; this is not a pipe/duct semantic detector. Legacy snapshots remain readable and have no classification switch. All original evidence is retained. Thin or reflective components and occluded surfaces remain capture limitations.

House viewer and mesh exports now share Studio's bounded corner mitres, with openings excluded. This fills small coincident endpoint corners only; it is not a complete Revit-style wall union or a repair for large missing scan segments. Export corner geometry belongs to the walls group.

Radiators now use passive geometric proposals and automatic evidence collection within the continuous House session, without a picking/confirmation panel. Equipment type remains unverified until reviewed after saving. RoomPlan does not supply a radiator class here; this is not a trained semantic classifier. Clean parametric walls in Technik and full wall T-junction unions remain unfinished. See HOUSE_RADIATOR_SURVEY.md for depth-availability and measurement limits.

House Studio replacements already use the newly selected family's default dimensions. Fit scanned size remains an explicit user action. Technical reclassification retains surveyed dimensions.

Real-device LiDAR validation is required; simulator tests cannot establish capture completeness or dimensional accuracy.

## Full-screen controls

Technik capture now fills the camera preview. Floating controls open the survey drawer, take a local pinned photo using a circular shutter, and toggle the live mesh overlay. Continuous mesh capture does not depend on shutter presses. Save and Close retain their existing save/discard safeguards. Alignment, manual equipment/pipe tools, AI preferences and diagnostics remain in the expandable drawer.

The saved mesh viewer has a full-screen action. Its floating display menu controls architectural surfaces, scan/MEP display and photo markers; Reset and Close remain accessible. This viewer is a virtual orbit view, not automatic placement of the saved model into a new live camera session. Resuming aligned AR still requires the existing recovery-map workflow.

Validation: mesh changes passed 240 macOS tests and 237 iOS simulator tests. A signed iPhone build passed. Final full-screen UI builds are checked separately; physical-device camera, thermal and scanning-quality checks remain required.


Live Technik mesh visibility: Show captured mesh is enabled by default and is applied directly when the camera host is created and on each update. The toggle no longer depends on an already-published viewport binding or an initial state-change callback. The filtered live preview now renders a bounded copy of ARKit mesh faces (up to 60,000 vertices, refreshed at most once a second), using a cyan wireframe. Ceiling is off by default in live and saved views. Only faces classified as ceiling are hidden; overhead ducts and unknown surfaces remain visible. The visibility toggle never deletes source evidence or changes raw mesh exports. A partial-preview label appears when the live vertex budget is exceeded. Saved capture retains the separate larger evidence budget. Physical-device rendering and performance checks are still required.

The live capture footer reports preview mesh faces, observed wall/floor classes and annotation counts. Pipe/duct/equipment annotation counts are not semantic detection totals. The survey drawer height adapts to landscape.
