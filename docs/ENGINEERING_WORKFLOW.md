# Engineering workflow — first implementation

Open a House or Technik scan's Studio. In More choose Engineering · renovation & issues, or select an object and use Engineering in its inspector.

## Included

- Persistent per-element records for scanned walls and editable furniture/MEP objects. Records use element UUIDs; the source scan package is never edited.
- Existing / Remove / Replace / New work statuses. Newly added or duplicated Studio models are New. Legacy projects default to Existing until classified by the user.
- All / Existing / Demolition / Proposed presentation views. Existing excludes New; Demolition includes Remove and Replace; Proposed excludes Remove. Replace is a single design element, not a pair of separately editable demolition and replacement objects. Use a separate New element and mark the old element Remove when two independent elements are needed.
- Phase-aware SceneKit rendering and PDF/SVG/DXF/USDZ/OBJ exports. Floors retain the surveyed footprint. CSV and JSON always retain all element records regardless of presentation filter.
- In Existing/Demolition, models use their stored reference envelope and orientation, and original family when retained. Older projects may not retain the original family. These are reconstructed parametric representations; raw scan packages remain the evidence source.
- A user can attest that all three current local dimensions have been independently checked, with instrument/surveyor/reference text and timestamp. Wall dimensions are length/height/thickness. This is a user assertion, not automatic metrological certification. Changes to size mark the attestation stale; position/rotation are not verified by this record.
- One current issue per element, with description, assignee, Open/In progress/Resolved status and notes. The register links back to the selected element. Undo/redo includes engineering records; removing an element removes its record, recoverable with Undo.
- CSV register with UUID, name, type, floor, phase, local dimensions in metres, verification, issue and notes. Text values are quoted and formula prefixes neutralised for spreadsheet safety. Dimensions are model envelopes, not bills of quantities, material volumes, nominal DN, capacities or procurement sizes.
- Engineering data is saved with the existing editable project JSON. Existing project JSON without the optional engineering field remains readable.

All source evidence stays independent. Scene edits and records require Save, as before. The element picker supports name/type search and caps visible matches at 200; narrow a search to reach additional elements.

## Remaining stages

The broader professional BIM roadmap is not complete in this release:

1. Reliable automatic radiator recognition, clean parametric Technik walls, complete corner/T junction wall unions and full measurement-device integration.
2. Editable architectural wall layers, levels, sections/elevations and opening schedules.
3. Connected MEP systems and ports, nominal sizing versus measured outside dimensions, insulation/service-clearance envelopes and technical calculation modules.
4. IFC semantic import/export and SmartBau round trips, BCF exchange, IDS checks and collaborative issue history. CSV/JSON are not substitutes for these standards.
5. Revisioned renovation alternatives, project-wide quantity/cost calculations and drawing-sheet layouts.
6. Multi-issue histories, attachment management, assignments/notifications and controlled project handover.

No code in this implementation infers equipment capacity, structural suitability, standards compliance or engineering accuracy from LiDAR geometry.

## Validation

245 macOS tests and 242 iOS simulator tests passed, including new tests for legacy JSON, record validation, phase filtering, unchanged source geometry, stale verification, undo recovery and CSV escaping. Final macOS and signed generic iPhone builds passed. Physical-device interaction and survey-accuracy validation are still pending.
