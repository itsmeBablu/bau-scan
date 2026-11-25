# Organized export review — Phase 3, local increment

Status: IN PROGRESS. This increment does not complete the full Phase 3 acceptance
criteria. No Apple build or Swift test has run on this Windows host. Capture-derived
data: device validation pending.

## Compatibility and output

Existing plans/, models/, studio/ and photos/ roots remain. One explicitly selected
technical survey retains technical-room/. Multiple selections use
technical-rooms/<sanitized-name>-<full-UUID>/. These are export selections, not
persistent associations or verified spatial registration. No native package or
Technical Room v1 schema changes or migrations are made.

House photos use photos/level-<index>/<room-name>/photo-01.jpg, etc. Unknown floors
use unassigned rather than an invented floor zero. Different room IDs with the
same sanitized name get suffixes such as Bath Room 2 within a floor. Numbers
restart per room and continue when revisiting it. Stored numbers are not changed.

photos/index.csv retains its original leading columns and appends identity,
filename and integrity columns. photos/index.json adds IDs, raw/display camera
poses, original/exported numbers, timestamps, sizes and SHA-256. Capture timestamps
are not substituted for unknown wall-clock dates. Coordinates are not GPS.
Unknown accuracy remains null. Invalid matrices throw before indexing. CSV text
escapes quotes and spreadsheet formulas; negative coordinates remain numeric.
Index paths reject absolute paths and parent traversal.

Each selected technical survey adds survey-details.json using the existing survey
exporter: annotations, corrections, dimensions, alignment, recognition and captured
meshes. technical-room-v1.json remains the existing handoff format. OBJ and mesh
DXF are omitted with an explanation when no mesh was captured. No point cloud or
equipment detection is fabricated.

With photos enabled, each technical survey includes numbered user camera photos,
ID-named annotation attachments and photo-index.json. Camera photos retain their
raw/aligned poses; attachments have null cameraPose when none was stored.
equipmentIDs and originalReference preserve annotation lookup. Hashes and sizes
describe exported bytes, including after privacy processing. External Google
Photos links are not added to the index. Names alone never attach a survey.

The manifest adds optional source identity, selected technical IDs, units,
coordinate notes and omissions. Inventory/hash validation still runs before ZIP
replacement. The README lists limitations. Existing destination protection and
cancellation remain delegated to the archive writer.

## Privacy and limits

A Mac export toggle removes source EXIF/GPS/IPTC metadata by re-encoding JPEG
copies and baking orientation into pixels. Originals are untouched. This is not
lossless or anonymization: visible content, names and camera poses remain. Default
exports preserve original JPEG bytes. The manifest describes the choice. Invalid
images fail explicitly rather than bypassing privacy. Privacy decoding accepts
single-image input up to 8192 pixels per side and 16,777,216 pixels total.

Technical selections are limited to 20 surveys and 256 MiB combined accounted
capture/attachment payload. This is not a measured peak-memory guarantee: JSON,
geometry and buffers add overhead; the individual read precedes the aggregate
check. Large exports still need memory profiling.

## Tests and evidence

Added OrganisedPhotoIndexTests: identity/pose/checksum, unknown accuracy/date,
invalid pose/path, CSV escaping and negative coordinates. Added
PhotoExportPrivacyTests: synthetic GPS/EXIF removal, orientation, original
preservation and invalid input. Extended TechnicalExportLinkTests: multiple
explicit IDs, deduplication and photos-only exclusion. All Swift tests are UNRUN,
including both complete schemes; XcodeGen generation is also unavailable here.

The Windows baseline .worktrees/phase3-local-evidence.json passes 13 service tests,
strict EN/DE localization (1,059 keys), six property-list files and diff whitespace.
The runner exits 1 because Apple schemes are BLOCKED. This does not validate Swift
compilation, image rendering or archive output. The service suite has one existing
Starlette/httpx deprecation warning.

Mac checklist: generate with XcodeGen; run both schemes; export same-name rooms,
multiple floors and two explicitly selected technical surveys; unzip with a standard
reader; compare every selected photo and manifest hash; verify camera/attachment
references; repeat privacy on/off; cancel over an existing ZIP and confirm its
bytes remain. Test native backup restoration independently. Use synthetic photos.

## Remaining work

Phase 3 remains open: granular content selection and counts, full native import/
restore comparison, finer project/floor/annotation identity where available,
standalone technical-package coverage, format-reader validation and synthetic ZIP
artifacts. No remote CI was run under the local-only instruction. Existing IFC and
native backup entry points remain; this increment does not include them in every
organized ZIP. Presets, optional unchanged native snapshots and separate-frame IFC
files have now been added; see EXPORT_PACKAGE_SPECIFICATION.md. Audio is explicitly
listed as absent; inspect the separate local
AR-notes branch before integration. English README scaffolding needs localization.
Scanner lifecycle, house regression, iCloud, accessibility, restoration and
engineering accuracy remain unverified on Apple hardware.
