# Mesh retention and architectural display

Technik capture uses its own ARKit mesh session, independently of House RoomPlan. New captures retain bounded latest-per-anchor geometry across sampled frames, so a final frame with fewer mesh anchors does not silently discard previously observed equipment. The cache keeps at most 250,000 vertices and replaces an updated anchor rather than layering its old triangles over the new version.

Plane detection is disabled for this session to avoid flattening shallow equipment into architectural planes. This changes newly scanned geometry only. The live camera has a Show captured mesh switch; mesh capture itself is independent of the display switch.

New snapshots preserve ARKit's per-face classification where available. In the saved viewer, Room surfaces hides classified walls, floors, ceilings, doors and windows. Unknown faces remain visible; this is not a pipe/duct semantic detector. Legacy snapshots remain readable and have no classification switch. All original evidence is retained. Thin or reflective components and occluded surfaces remain capture limitations.

House viewer and mesh exports now share Studio's bounded corner mitres, with openings excluded. This fills small coincident endpoint corners only; it is not a complete Revit-style wall union or a repair for large missing scan segments. Export corner geometry belongs to the walls group.

Radiators still use assisted close-up capture within the continuous House session. RoomPlan does not supply a radiator class here. The scanning UI now explicitly states that the user must mark the radiator's front corners and adjacent wall. Automatic radiator recognition, clean parametric walls in Technik, and full wall T-junction unions remain unfinished.

House Studio replacements already use the newly selected family's default dimensions. Fit scanned size remains an explicit user action. Technical reclassification retains surveyed dimensions.

Real-device LiDAR validation is required; simulator tests cannot establish capture completeness or dimensional accuracy.

## Full-screen controls

Technik capture now fills the camera preview. Floating controls open the survey drawer, take a local pinned photo using a circular shutter, and toggle the live mesh overlay. Continuous mesh capture does not depend on shutter presses. Save and Close retain their existing save/discard safeguards. Alignment, manual equipment/pipe tools, AI preferences and diagnostics remain in the expandable drawer.

The saved mesh viewer has a full-screen action. Its floating display menu controls architectural surfaces, scan/MEP display and photo markers; Reset and Close remain accessible. This viewer is a virtual orbit view, not automatic placement of the saved model into a new live camera session. Resuming aligned AR still requires the existing recovery-map workflow.

Validation: mesh changes passed 240 macOS tests and 237 iOS simulator tests. A signed iPhone build passed. Final full-screen UI builds are checked separately; physical-device camera, thermal and scanning-quality checks remain required.
