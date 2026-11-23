# Revit IFC export

The Foundation-only export API accepts an optional House, technical annotation
documents, and RevitExportOptions. The export sheet supplies the platform UI adapter.
IFC4 Reference View is the target. IFC2x3 uses concrete distribution base classes
where the more specific IFC4 occurrence class is unavailable.
Model View Definition certification and Revit interoperability remain unverified.

## Placement

TechnicalRoom.shellToRoom maps shell coordinates into room coordinates.
Registered exports apply its inverse, then the explicit shellPlacements entry.
The shell ID must match a room in the House. Missing registration is an export error.
Exporting without a House retains the room frame and writes a standalone warning.

RevitScanEvidence reads neutral structure JSON and checks house/room identities
and wall evidence before supplying shared-frame registration. It uses the median
observed floor elevation for each story. The export sheet can read this evidence
when the subject exposes a house USDZ alongside structure.json.
Without floor evidence, storey elevations accumulate the preceding exported
story's maximum scanned room height. The first exported story starts at zero.
Structural separation and omitted intermediate stories are unknown. These
elevations are labelled estimates in the IFC.

Room coordinates (x,y,z) become IFC coordinates (x,-z,y), in metres.
The determinant is +1. Bau's documented layout mapping uses (x,z,y) and millimetres.
That is a different layout convention and must not be substituted for IFC conversion.
Equipment uses the transformed local width and up directions so yaw is preserved.

## Geometry and evidence

Walls are per-room wall extrusions, with relationships to opening voids and fillings.
This module does not merge party walls. Floor slabs use the existing presentation
thickness, explicitly labelled. Room names and net polygon areas are exported.
Pipes use effective centrelines, circular profiles and separate endpoint elevations.
Ducts use effective points and rectangular profiles. Their roll is unspecified by the
current annotation model, so the exporter chooses a deterministic perpendicular.
Fittings have semantic class and placement but no fabricated dimensions or solid.
The current model has pipe-hosted fittings only.

Each MEP occurrence and distribution port has Bau_Provenance. Null accuracy stays an
unset IFC property. Full field wrappers are also retained as JSON in
Bau_FieldProvenance for manually annotated equipment, pipes, ducts, fittings and
equipment ports. Existing source values remain available. Capture-derived results
are labelled device validation pending.

Calibration is length-only in the existing annotation model. The IFC retains
geometric lengths and the correction factor separately. Coordinates and entered
equipment sizes are not silently rescaled.

## Validation

RevitIFCExportTests includes semantic golden count files for all three technical
fixtures and the real house, deterministic bytes, GUID encoding, escaping,
asymmetric coordinates, storey elevations, vertical endpoints, edited points,
combined registration and port connections.

On Windows the XcodeGen and both xcodebuild test commands were attempted and could
not run because the tools are unavailable. Swift tests are unrun.
The optional Python validator's syntax and CLI were checked with the already
installed IfcOpenShell. Entity attribute counts were checked for 16 IFC4 classes
and seven concrete IFC2x3 fallback classes. No Swift-generated IFC has yet been
opened in IfcOpenShell or Revit.

After exporting on Mac, run:

    python Scripts/validate_ifc.py Survey.ifc --storeys 1

Then open and link the result in the target Revit version and inspect wall voids,
storeys, equipment, vertical pipes, units and connector relationships.
