# Design Studio

Open **Studio** from the iPhone library toolbar or **Design Studio** from the Mac sidebar. Choose **House** or **Technik Room**, then a saved scan. Saved room/House screens also offer **3D Edit** in Options; saved technical surveys offer a Technik Studio action.

## Independent storage

Studio copies the shell and recognised object dimensions into a separate design. Save writes `SceneEdits/<source-kind>-<source-UUID>.json` alongside the library folders, never into `.roomscan`, `.housescan` or `.technicalroom` evidence. There is one saved working design per source. Export the editable JSON project to keep additional variants; importing a variant into the same source is undoable. Designs remain listed even if their source is later removed. JSON records source IDs, scanned size/placement references, chosen families, colours/materials, themes and equipment metadata.

## House Studio

Recognised RoomPlan objects become native parametric models. Available families include sofas, beds, chairs, tables, TVs, cabinets, appliances, bathroom fixtures, radiators and generic boxes/cylinders. Construction uses bounded native shapes and PBR materials; this is an independent native implementation inspired by SmartBau's parametric approach, not a bundled copy of its Three.js renderer or an imported model collection.

Models fit the scan bounding dimensions. Sofas vary cushion count, beds adapt pillow count, cabinets vary module count and radiators vary section count. Model replacement retains chosen dimensions. **Fit scanned size** and **Restore scan position** restore saved references. Appearance remains a generic representation rather than exact identification of a manufacturer's furniture.

Tap/click an object or choose it in the inspector. Choose **Move objects** to drag on its horizontal plane. Edit XYZ, dimensions and yaw numerically for precision. Orbit mode retains camera controls. Undo/redo supports design edits. Native forms, menus, file panels and unsaved-change protection are used on both platforms.

House appearance offers Natural, Scandinavian, Modern, Industrial and Pastel palettes, custom wall/floor colours, day/night and summer/winter lighting mood. Rounded shapes, a small repeating floor texture, ambient occlusion and one shadow light aim toward the supplied references, without claiming identical offline-render quality. Season is presentation only. Geometry/texture sizes and object counts are bounded; real iPhone performance still needs profiling.

## Technik Studio

Only accepted recognition results seed detected pipes/ducts. Manual survey routes and equipment also seed editable reconstructions. Unreviewed detections are not silently promoted. Unknown equipment can be added manually using generic shapes. Hidden routes/connections are never fabricated.

MEP models use sharp measured envelopes without decorative chamfers, artificial fittings or furniture smoothing. Pipe/duct lengths, cross-sections and accepted rectangular-duct roll are retained. Captured colours are preserved when supplied by accepted recognition, labelled as camera-sampled and distinguishable from presets/custom colours; captured colour can be restored after editing. Material identity is not inferred from colour. Equipment without sampled colour uses a labelled neutral preset. Original mesh colours/evidence remain in the survey viewer.

Equipment data supports manufacturer/model, kW, litres, m³/h, bar and required front service clearance. Values require a nameplate, manufacturer or calculation reference and are never inferred from scan size. Linked German planning resources include DIN EN 12828, DIN EN 12831-1, VDI 2050, VDI 2035, VDI 6022 and DVGW drinking-water/W 551 material. The applicable edition, manufacturer instructions, state-specific requirements and utility conditions need project-specific review; no standards text, default capacity, universal installation spacing or compliance certificate is generated.

## Snapping and overlaps

Drag placement can snap to a 0.05 m grid and nearby wall surfaces. Numeric entries are not rounded. New/duplicated objects seek a free location. Moves/resizes reject oriented-envelope intersections with objects/walls and penetration below the floor beyond a 0.002 m numerical tolerance. Touching is allowed. **Allow overlaps** is an explicit override for intentional connections. **Check current floor overlaps** reports up to 20 issues already present in the reconstructed design. These are conservative envelope checks, not raw-mesh clash analysis or verification of manufacturer maintenance zones. Existing scan evidence is not changed to resolve collisions.

Studio wall mitres fill only solid endpoints within 0.025 m, with bounded corner geometry. Openings, larger gaps and cutaway visibility are respected. Original wall measurements and assumed wall thickness remain unchanged.

## Export

- PNG: 1920 × 1440 rendering of the current camera, cutaway and lighting, with selection highlight removed; save using the native file panel.
- JSON: full editable Studio project, restricted on import to the same source ID/type.
- USDZ / OBJ-with-materials ZIP: complete walls and modelled objects of the selected floor. Floors are exported separately because the neutral shell model does not reliably retain their original vertical separation.
- PDF / SVG / DXF: edited 2D design footprints using metres. These are schematic design outputs, not certified engineering drawings. Equipment metadata is retained in the editable project.

Live transparent AR recognition overlays are a proposed next stage, not part of this Studio implementation. Automatic boiler/heater recognition, nameplate OCR, universal German sizing rules and verified engineering accuracy are not claimed. Physical camera/depth/placement validation and device performance profiling remain required.

## Validation · 2026-11-21

233 Mac tests and 228 iOS simulator tests passed, along with the signed generic iPhone build. Studio checks cover original-package byte preservation, project round trips, provenance/invalid data, smart furniture fitting, accepted-only MEP seeds, rectangular-duct orientation, sharp technical envelopes, oriented overlap checks, touching faces, snapping, wall joins/openings, image rendering and JSON/PDF/SVG/DXF/USDZ/OBJ exports. Mac UI checks exercised the mode picker, object inspector and unsaved-save-and-close flow. Accessibility automation intermittently timed out during repeated navigation; full gesture usability and iPhone performance/accuracy testing remain pending. No cloud AI calls, billing changes or new recognition models were introduced by Studio.
