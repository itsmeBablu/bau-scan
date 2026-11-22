# Studio architecture and controls refinement

## Compact editing and dimensions

Studio retains its full-screen canvas. Portrait controls now form one low dock at the bottom safe-area edge: Models, Move, Edit, Style, Sizes and More. Undo/redo, reset, export and engineering tools remain under More. Landscape uses the same compact horizontal dock with the optional inspector beside it. Touch targets retain a 44-point minimum; the home-indicator safe area stays clear.

Sizes toggles charcoal 3D dimension lines and camera-facing metre labels. Up to 64 visible wall lengths plus the selected object's local width, height and depth are shown. Selection and floor changes update the labels. PNG captures include visible labels; model exports omit this display overlay and keep their existing measured 2D drawing dimensions.

House Studio offers wood, tile or plain floor finishes. The default wood texture repeats over 0.72 m (four 0.18 m rows); tile repeats over 0.30 m. Pattern repeat is adjustable from 0.1–2 m. These are design patterns, not inferred product sizes. Technik retains its neutral survey floor.

## SmartBau source adaptation

The following files were inspected read-only in the user's private `try-bau/SmartBau` repository:

- `apps/web/lib/windowGeometry.ts`, blob `acf3a1bf590f34b971f4b6cbe56fdc4458cb47bf`.
- `apps/web/lib/straightWallMeshBuffers.ts`, blob `c55b9400ff5bf7fb08d20900bc2cb5937226c1b6`.
- `apps/web/lib/wallDisplayEdges.ts`, blob `04fb097f60c7ff840f304bd8d434703815cd64d4`.
- `apps/web/lib/sceneGeometryArchitecture.md`, blob `c1f9922fa8b7acac0e22e9fc1575acb14f0a11de`.

Native SceneKit code adapts the straight face-profile/opening and through-depth mitre construction approach, and window rail/glazing dimensions/materials. No Three.js runtime, whole SmartBau asset library or SmartBau project files are bundled. SmartBau itself was not changed.

Walls now use a continuous front/back cell profile around opening holes, with internal subdivision caps omitted. Mitres join solid near-coincident endpoints (25 mm maximum). Acute/large missing corners and endpoints intersecting openings remain conservative; no hidden wall segments are invented. Captured wall lengths/centrelines are unchanged. This is not a full Revit wall union or multi-way junction solver.

House windows use four nonoverlapping frame rails and inset glazing, fitted to the captured opening. Glass does not write depth, reducing transparent-surface conflicts. A closed generic window is a presentation model; operation, manufacturer, thermal performance and sash type are not inferred.

## Surface stability and performance

Exact coincident architectural triangles are removed. Coplanar floor overlaps are clipped against previously covered room regions, retaining source contours independently. This is bounded display coverage repair, not a volumetric CAD boolean: very complex regions fall back to original geometry when the clipping budget is exceeded. Intentional design-object overlaps and unresolved capture errors still require review.

Annotation/issue/verification-only changes no longer rebuild the entire SceneKit scene. Rendering keys include geometry, materials, construction overrides, renovation filters and lighting, while excluding nonvisual metadata. Dimension visibility/selection triggers only the required overlay rebuild. Record lookups use a nonserialized index; the original JSON schema remains compatible.

## Room names and saved-model AR

House Measurements room rows now open Rename room. Names are stored in the derived House model, survive raw-backed reconstruction and update its plan/exports. Raw RoomPlan structure and survey sidecars remain intact. Standalone Room Measurements also exposes its existing rename action.

Saved-model AR refreshes camera authorization, starts after the native view has nonzero visible layout, stops when its screen disappears, resumes after interruptions and creates a fresh AR view when restarted. Failure/watchdog guidance remains visible. Real iPhone validation is required: simulator tests and a signed build cannot confirm live camera opening, plane placement, recognition rates or measurement accuracy.

## Navigation

Profile and Settings are combined. Main tabs are House, Technik, Capture, Studio and Profile. Google sign-in/account details and app preferences are under Profile; macOS retains Settings and its sidebar. Google authentication remains unavailable until the documented OAuth configuration is supplied.


Validation: 262 macOS and 260 iOS tests passed. The two portrait/landscape Studio layout tests passed again after the final dock positioning adjustment. Native tab/Studio layouts and a SceneKit-rendered architectural fixture were inspected; the final signed iPhone build passed. Regression tests cover floor coverage area, duplicate surfaces, opening holes and corner mitres, window rails, 3D dimension nodes, metadata-only scene reuse, indexed lookup, room-name persistence, thickness provenance and automatic radiator proposals.
