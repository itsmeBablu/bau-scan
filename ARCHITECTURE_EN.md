# Architecture — dWalkScan (source of truth)

**Platforms:** iPhone (iOS 18+, LiDAR) scans, views, exports · Mac (macOS 15+) views, measures, exports, prints, auto-updates via Sparkle · iCloud Drive syncs both and exposes files to third-party apps. One shared codebase, two XcodeGen targets (`RoomScanner`, `RoomScannerMac`), one SPM dependency (Sparkle, Mac only). Public repo `BabuReddy/dWalkScan`, landing page on GitHub Pages (`/docs`).

_Mirror: `ARCHITECTURE.md` (French). Edit both in the same change._

Build audit correction (Phase 0): `project.yml` currently defines GoogleSignIn on
both targets and Sparkle on macOS, rather than the single dependency described in
the historical overview above. Swift language mode is 5.9. The baseline CI uses
the default toolchain on macos-26; minimum deployment targets remain iOS 18/macOS
15. Newer UI APIs also have compiler/platform guards; old-toolchain compatibility
has not been established by this audit.
Apple builds for the quality-review branch are UNVERIFIED on this Windows host.

## Overview

```
SwiftUI UI ─▶ RoomCaptureView (Apple RoomPlan) ─▶ CapturedRoom
                                                     │
                                          FloorPlanBuilder
                                                     ▼
                          House { Story { [FloorPlan] } }  (pivot, pure Swift; v1 = 1 room)
                                                     │
        ┌──────────────┬──────────────┬──────────────┼──────────────┬──────────────┐
   PlanRenderer     SVGExporter   DXFExporter   USDZExporter   JSONExporter   PlanSceneBuilder
   (PDF / PNG /                                 └▶ ModelIOConverter            └▶ RealityView (SwiftUI)
    floor texture)                                  (OBJ/STL/PLY)                 3D orbit · 2D top-down · AR (iOS)
                                                     │
                                        ExportService ─▶ ShareLink
                                                     │
                RoomStore ─▶ StorageLocation (iCloud ubiquity container │ local fallback)
                  <container>/Documents/Rooms/<uuid>.roomscan  ·  <container>/Documents/Exports/<Room>/
                  UbiquityMonitor (NSMetadataQuery, download, conflicts)  ⇄  iPhone ↔ Mac ↔ Files / Finder
```

## Layers

| Layer | Folder | Responsibility | Depends on |
|---|---|---|---|
| App | `RoomScanner/App` | Entry point, global observable state, dependency injection | UI, Storage |
| Scan (iOS only) | `RoomScanner/Scan` | Wraps `RoomCaptureView`, **owns the injectable `ARSession`** (shared frame for multi-room v2), delegate → `CapturedRoom`, error mapping | RoomPlan, ARKit |
| Domain | `RoomScanner/Domain` | `ScanInput` (neutral scan snapshot), `FloorPlan` / `House` / `Story` pivot types, `FloorPlanBuilder` (ScanInput → 2D projection), `WallGeometry` (wall boxes / panels shared by viewer and mesh export), `Measurements`, `RoomNaming`; v2: `StructureInput` (per-room scans in a shared world frame + merged surfaces), `StoryDetector` (stories from floor heights), `HouseBuilder` (StructureInput → `House`) | Foundation, simd only (RoomPlan types are consumed at the boundary) |
| Viewer | `RoomScanner/Viewer` | `PlanSceneBuilder` (House → RealityKit entities), `ViewerView` (SwiftUI `RealityView`, shared iOS/macOS), `ViewerMode` (3D / 2D zenith camera), `ARPlacementController` (iOS: `SpatialTrackingSession`, plane anchors, 1:20 / 1:50 / 1:1), `ViewerControls` | Domain, RealityKit, Export (floor texture from `PlanRenderer`) |
| Export | `RoomScanner/Export` | `ExportFormat` (groups, `UTType`), `ExportService` (temp folder, sanitized file names, `availableFormats`), `PlanRenderer` (PDF/PNG/thumbnail/floor texture), `SVGExporter`, `DXFExporter`; USDZ copied from the package; `PlanMeshBuilder` + `MeshWriters` (OBJ/STL/PLY from the plan), `ModelIOConverter` (scan mesh) | Domain, Core Graphics, Model I/O, RoomPlan (USDZ) |
| Storage | `RoomScanner/Storage` | `RoomStore` (CRUD of `.roomscan` and `.housescan` packages, iCloud activation/switch, import, exports to `Exports/<Room>/`), `RoomPackage` (UTType, `NSFileCoordinator`), `StorageLocation` (iCloud or local root), `RoomRecord`, `CloudAvailability` (container resolution off main thread, `setUbiquitous` migration), `UbiquityMonitor` (`NSMetadataQuery` → `CloudItemStatus`, auto-download), `ConflictResolver` (`NSFileVersion`, newest wins, "(conflict)" copy with new UUID) | Domain, Export (thumbnail), Foundation |
| Sync | `RoomScanner/Sync` | `UbiquityMonitor` (`NSMetadataQuery` live list, download-on-demand, per-room status), `CloudAvailability` (iCloud ↔ local switch, migration), `ConflictResolver` (`NSFileVersion`) | Storage, Foundation |
| MacUI | `RoomScanner/MacUI` (macOS target only) | `MacRootView` (`NavigationSplitView`, search, context menu, package drag), `MacAppState` (selection + menu actions via `focusedSceneValue`), `MacMenuCommands` (⌘O import, ⌘E export + per-format submenu, ⌘P print, ⇧⌘R Reveal in Finder, open library folder), `PrintController` (`NSPrintOperation` on the vector PDF), `DragExportProvider` (`NSItemProvider.registerFileRepresentation`, generated on demand), `OpenWithMenu` (`NSWorkspace.urlsForApplications(toOpen:)`), `MacEmptyStateView`, `UpdaterController` (Sparkle `SPUStandardUpdaterController`, started only when `SUPublicEDKey` is present) | UI, Export, AppKit, Sparkle |
| UI | `RoomScanner/UI` | SwiftUI screens: list (delete confirmation, settings), detail (Plan 2D / 3D / Measures), export sheet, `CloudStatusBadge`, error screens, `SettingsView` (iCloud toggle, folder, updates on Mac, about) | App, Domain, Export, Storage, QuickLook |

Rules: **Domain, Export, Storage and Sync never import SwiftUI, UIKit or AppKit**; Viewer's `PlanSceneBuilder` is pure RealityKit (testable), only `ViewerView`/`ViewerControls` are SwiftUI; Export depends on RoomPlan only in `USDZExporter`; `PlanRenderer` is pure Core Graphics (`CGContext` PDF and bitmap) so it renders identically on both platforms; `Scan/` and `ARPlacementController` are excluded from the macOS target (RoomPlan does not exist on macOS, verified).
Everything below UI is testable on the simulator from JSON fixtures.

## Key types

- `CapturedRoom` (Apple, `Codable`) — persisted as-is in `room.json`; source of truth for v2 merging. **Readable on iOS only** (RoomPlan does not exist on macOS).
- `ScanInput` — platform-neutral snapshot of a scan (`ScanSurface`/`ScanObject`: category, `dimensions`, `transform` simd, confidence, parent id, polygon corners). Produced by `CapturedRoomAdapter` (`Scan/`, iOS); the only input of `FloorPlanBuilder`; what tests and fixtures use on both platforms. Persisted as `scan.json`.
- `House` — `stories: [Story]`, `Story` — `index, rooms: [FloorPlan]`. Every renderer, scene builder and exporter takes a `House`; v1 always holds one room (D14).
- `FloorPlan` — `walls: [Wall]`, `openings: [Opening]`, `objects: [PlacedObject]`, `floorPolygon: [Point2D]`, `ceilingHeight: ClosedRange<Double>`, `bounds`, `transform` (placement in the house frame, identity in v1). Metres, `Double`, `Codable`, `Equatable`. Persisted as `plan.json` (with `schemaVersion`) so the Mac can read it without RoomPlan; recomputed from `room.json` on iPhone when the schema changes.
- `RoomMeasurements` — area (shoelace), perimeter, ceiling min/max, per-element lists.
- `HouseMeasurements` — house floor area as the **union** of the rooms of each storey (storeys are added, since they stack in plan), room and storey counts. Adjacent rooms overlap slightly (wall thickness, imprecise scan outlines), so summing their areas double-counts — measured at +2.14 m² on the first real house (D27). `Polygon2D.unionArea` runs inclusion–exclusion and only ever clips by a triangle, the one case where Sutherland–Hodgman is valid.
- `RoomNaming` — a room is named from **every** RoomPlan section of its capture ("Dining room / Kitchen"): one `CapturedRoom` can carry several sections. `.unidentified` is dropped as soon as another section exists; duplicates get a counter ("Bedroom 2").
- **No house-level de-duplication (D26)** — on the first real `CapturedStructure`, no wall identifier is shared between two rooms: `StructureBuilder` drops 7 per-room walls and synthesises 3 (52 → 48), and merges the 3 room floors into 1. Doors, windows, openings and objects pass through unchanged. The party wall is therefore a rebuild, not a duplicate we could detect — `StructureInput.mergedWalls` / `mergedFloors` carry Apple's merged surfaces for house-level geometry; per-room `FloorPlan`s stay the source for everything per-room.
- `ExportFormat` — `pdf, png, svg, dxf, usdzParametric, usdzMesh, obj, stl, ply, json, zip` with `UTType`, extension, localized label.
- `RoomRecord` — `meta.json`: `id, name, createdAt, label, areaM2, storyIndex, schemaVersion`.
- `RoomPackage` — the `.roomscan` package (UTType `io.github.itsmebablu.dwalkscan.room`, conforms to `com.apple.package`): `room.json`, `room.usdz`, `meta.json`, `thumbnail.png`. Seen as one file in Files/Finder; double-click opens the Mac app; AirDrop-able.
- `StorageLocation` — protocol over the storage root: iCloud ubiquity container (`iCloud.io.github.itsmebablu.dwalkscan`) when `ubiquityIdentityToken != nil`, else local Documents.

## Coordinate conventions

- RoomPlan: Y up, floor = XZ plane, metres. Surface `transform` (4×4) + `dimensions` (width, height, depth).
- Wall segment: centre `(t.x, t.z)`, direction = column 0 of `transform` projected on XZ; endpoints = centre ± dir × width/2.
- Plan 2D: `x_plan = x_room`, `y_plan = −z_room` (top-down view). Wall graphic thickness: constant 0.10 m (RoomPlan does not measure it).
- Window sill height = `(t.y − height/2) − floorY`.

## RealityKit viewer (D13)

- SwiftUI **`RealityView`** (iOS 18+ / macOS 15+ — the reason for the deployment targets), one component shared by both platforms. `content.camera = .virtual` for the 3D and 2D modes with the built-in `realityViewCameraControls(.orbit)` / `.pan` + `.dolly`; `content.camera = .spatialTracking` for AR on iOS (camera passthrough, `SpatialTrackingSession`, `AnchorEntity(.plane(.horizontal, …))`).
- Scene is **parametric**, built from `House` by `PlanSceneBuilder`: one root entity per house, one child per room (positioned by `FloorPlan.transform`); walls = `generateBox` (length × height × 0.10 m), walls with openings split into 3 boxes + panel (door: thin brown box; window: translucent blue box); floor = `generatePlane` textured (`UnlitMaterial`) with the 2D plan PNG from `PlanRenderer`; objects = grey translucent boxes + label; optional 3D dimension labels.
- Modes: **3D** (`.virtual`, orbit controls), **2D** (`.virtual`, zenith `PerspectiveCamera`, walls flattened to 0.02 m, pan/dolly only), **AR** (iOS only — `.spatialTracking`, horizontal plane anchors, tap to place at 1:20 / 1:50 / 1:1, drag / two-finger rotate). Switching modes only changes `content.camera`, the virtual camera and wall visibility; entities are built once.
- QuickLook on `room.usdz` kept as a secondary "Quick preview" button.

## Export specifications (summary)

| Format | Implementation | Units |
|---|---|---|
| PDF | `PlanRenderer.pdfData` — `CGContext` PDF (Core Graphics / Core Text), A4 landscape, standard scale (1:20/25/50/100), title block; also used for Mac printing | pt (drawing in m → scaled) |
| Floor texture | `PlanRenderer` "texture" mode (no title block), consumed by `PlanSceneBuilder` | px |
| PNG | `PlanRenderer.pngData` — `CGContext` bitmap @3× + `CGImageDestination` | px |
| SVG | `SVGExporter` text writer, `viewBox` in mm (y flipped), `<g id>` floors/objects/walls/doors/windows/openings/dimensions/text, arrow markers, door swing `<path>` arc | mm |
| DXF | `DXFExporter` R12 ASCII: `HEADER` (`$ACADVER` AC1009, `$INSUNITS`=6, `$EXTMIN/MAX`), `TABLES` LTYPE/LAYER (WALLS, DOORS, WINDOWS, OPENINGS, FLOOR, OBJECTS, DIMENSIONS, TEXT)/STYLE, `ENTITIES` (walls and objects as closed `POLYLINE`, door `ARC`, dimension `LINE` + ticks + centred `TEXT`) | m |
| USDZ | `CapturedRoom.export(to:exportOptions:)` at scan time: `.parametric` → `room.usdz`, `.mesh` → `room-mesh.usdz`; exports copy them (Model I/O cannot write USDZ, verified) | m |
| OBJ/STL/PLY | default: `PlanMeshBuilder` (`TriangleMesh` from `House`: wall boxes via `WallGeometry`, door/window panels, polygon floor slab, objects; groups walls/doors/windows/floor/objects) + `MeshWriters` (OBJ text, STL binary, PLY ASCII); option "scan mesh": `ModelIOConverter` (`MDLAsset(url: room-mesh.usdz).export(to:)`), off main thread | m, y up, z = −y_plan |
| ZIP | `ArchiveExporter`: every export + localized `README.txt` in `<Room>/`, zipped through `NSFileCoordinator(.forUploading)` (no dependency, iOS + macOS) | — |
| JSON | `plan.json` content (`FloorPlan`, `RoomPackage.encoder`) — readable on both platforms, unlike Apple's `room.json` | m |
| ZIP | all of the above + README.txt | — |

## Storage layout & iCloud sync (D6, D16, D17)

```
<root>/Documents/                      root = iCloud container (shown as "iCloud Drive / dWalkScan") or local fallback
  Rooms/<uuid>.roomscan/               package = one file in Files / Finder
    room.json       CapturedRoom (source of truth; iOS-only readable)
    scan.json       ScanInput (neutral snapshot)
    plan.json       FloorPlan (schemaVersion) — read by the Mac and the exporters
    room.usdz       parametric export, written at save time
    room-mesh.usdz  raw scan mesh (optional, iPhone capture only)
    meta.json       RoomRecord
    thumbnail.png   600×400 plan preview
  Exports/<Room name>/<Room name>.pdf|dxf|svg|usdz|obj…   "Save to iCloud Drive" — readable by any 2D/3D app on both devices
  Houses/<uuid>.housescan/             v2 — one package per house (UTType io.github.itsmebablu.dwalkscan.house)
    meta.json             HouseRecord (name, room/story counts, area)
    house.json            House (stories → FloorPlans, shared world frame) — rebuilt from structure.json when present
    structure.json        StructureInput (neutral: per-room ScanInputs + merged surfaces)
    structure-apple.json  CapturedStructure (iOS-only readable; source of truth)
    rooms/<uuid>.roomscan nested room packages (not listed as standalone rooms)
    house.usdz            parametric export of the whole structure
    thumbnail.png         ground-floor preview
```
- Root chosen at launch by `StorageLocation`; local → iCloud migration offered when iCloud becomes available.
- Live listing via `NSMetadataQuery` (ubiquitous documents scope, `*.roomscan`), status badge from downloading/uploaded keys; download-on-demand with `startDownloadingUbiquitousItem`.
- Every read/write goes through `NSFileCoordinator`; a package is written in one coordinated operation so it arrives complete on the other device.
- Conflicts (`NSFileVersion`): newest wins, the other is kept as `<name> (conflict).roomscan` — a scan is never lost.
- Info.plist on both targets: `NSUbiquitousContainers` with `NSUbiquitousContainerIsDocumentScopePublic = true`, `NSUbiquitousContainerName = "dWalkScan"`; `UTExportedTypeDeclarations` for `.roomscan`; Mac adds `CFBundleDocumentTypes`.
- Entitlements: iCloud Documents + container `iCloud.io.github.itsmebablu.dwalkscan` (both — created automatically by `xcodebuild -allowProvisioningUpdates`, as for TheNews); Mac adds App Sandbox, user-selected files r/w, print, network client, Sparkle mach-lookup exceptions (`-spks`, `-spki`); a `-Release.entitlements` sets `icloud-container-environment = Production` for the DMG.
- Temporary exports live in `tmp/` and are regenerated on demand. iOS keeps `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` for the local fallback folder.

## Error handling

`enum AppError: LocalizedError` — `unsupportedDevice`, `cameraDenied`, `scanFailed(RoomPlan.Error)`,
`exportFailed(format, underlying)`, `storageFailed`, `cloudUnavailable`, `downloadFailed`, `conflictResolved(kept:)`. `room.json` is written **before** any conversion so
an export failure never loses a scan. RoomPlan errors are mapped to human-readable localized messages.

## Mac auto-update (D18)

Sparkle 2 (SPM, Mac target only). `SUFeedURL` → `appcast.xml` at the repo root on `main` (raw GitHub); `SUPublicEDKey` embedded; the EdDSA private key lives in the login keychain (account `RoomScanner`), generated **once** and backed up — never regenerated. Sandboxed app → `SUEnableInstallerLauncherService = YES`. `Scripts/release.sh` (from `Templates/Scripts/release-full.sh`) builds, signs (Developer ID, hardened runtime), notarizes, staples, packages the DMG into `release/`, runs `sign_update` and rewrites `appcast.xml`.

## Delivery (D19)

Public repo `BabuReddy/dWalkScan`. One branch per phase `feat/phase-N-<name>` → PR → merge to `main`, chained without intermediate approval; tags and GitHub Releases are always confirmed by Vincent. Landing page `docs/index.html` (GitHub Pages from `/docs`, trilingual, hub `assets/base.css`), a row in the `BabuReddy.github.io` hub and an entry in the profile README.

## Testing strategy

- Simulator **and macOS** (same test sources run on both): unit tests for Domain (fixtures + synthetic rooms), golden-file tests for SVG/DXF,
  structural DXF validation, PNG sanity, `PlanSceneBuilder` entity count/placement, `RoomStore`/`RoomPackage` on a local `StorageLocation` in a temp directory, `ConflictResolver` with mocked versions.
- Device: manual checklist (scan accuracy vs tape measure < 2 %, each export opened in an external
  reader: Preview, LibreCAD/QCAD, Blender, Files; iCloud round-trip iPhone → Mac < 1 min, airplane-mode fallback, `.roomscan` AirDrop import; Mac double-click, ⌘P, drag & drop, Open With).

## Decisions log

See §3 of the design spec (`docs/superpowers/specs/2026-09-05-3dscanner-design.md`): D1 RoomCaptureView,
D2 SwiftUI, D3 pivot model, D4 hand-written 2D writers, D5 Model I/O for OBJ (glTF v2), D6 file storage,
D7 single room v1, D8 share sheet, D9 metric units, D10 no SPM deps, D11 fr/en, D12 naming (to confirm),
D13 RealityKit `ARView` viewer (3D / 2D / AR) built parametrically from `House`, D14 house-ready aggregate `House` + shared `ARSession` from v1,
D15 Mac companion on the shared codebase (two targets, pure Core Graphics renderer, no scan on Mac), D16 iCloud Drive ubiquity container as primary storage with local fallback (CloudKit rejected: exposes no files to third-party apps), D17 `.roomscan` package type,
D18 Sparkle auto-update on Mac, D19 public repo + branch per phase + landing page.

## v2 readiness (whole house)

- Scan flow v2 (done, device validation pending): `ScanCoordinator(mode: .house)` keeps one `ARSession` across rooms (`RoomCaptureView(frame:arSession:)`, `stop(pauseARSession: false)`), accumulates `CapturedRoom`s, then `StructureBuilder(options: [.beautifyObjects]).capturedStructure(from:)` → `CapturedStructure` → `CapturedStructureAdapter` → `StructureInput` → `HouseBuilder` → `HousePackage.assemble` → `.housescan`. `ScanView` drives it with "Room done" / "Next room" / "Finish the house"; the library toolbar offers "Scan a room" / "Scan a house" (`ScanMode`).
- Downstream: `PlanRenderer`, `PlanSceneBuilder` and every exporter iterate over `house.allRooms`. Houses get one PDF page per story (`PlanRenderer.pages(of:)`, PNG pages stacked vertically) and a pastel floor tint per room (`PlanRenderer.roomPalette`, applied to the 2D plan and to the 3D floor texture); `HouseDetailView` filters plan, viewer and measures by story.
- Storage v2 (done): `Documents/Houses/<uuid>.housescan/` packages (`HousePackage`, `HouseRecord`); `RoomStore` exposes `houseRecords`, `saveHouse`, `house(for:)`, `importAny`; `LibraryItem` (room | house) drives the two-section library on iOS and the Mac sidebar; `ExportSubject` (room | house) is the single input of `ExportService`, `ExportSheet`, `DragExportProvider` and the archive README. Remaining: multi-room capture on iPhone (`CapturedStructureAdapter`), shared-wall dedup, `.housescan` conflict resolution.

## Design system — S0 audit (2026-11-26)

S1 implementation: the existing AppTheme.swift now lives in DesignSystem/, alongside
DS.swift, fixed ExportPalette.swift and Colors.xcassets. AppTheme is a compatibility
facade over the same tokens, not a parallel theme. DS namespaces color roles,
spacing, radii, stroke, shadow, system typography, accessible sizes and Reduce
Motion-aware animation. ScaledSizes provides a Dynamic Type-relative thumbnail.
ColorToken.platformColor bridges the named assets for UIKit/AppKit rendering.

AccentColor is the single app accent: dark amber on light surfaces, brand-family
yellow on dark surfaces, with explicit increased-contrast variants. Brand remains
#facc15 fill with dark OnBrand. Root application scenes apply dsAppTheme once;
eight blue overrides are removed. Recording and camera indicator roles are the
only centralized semantic tint exceptions. The native prominent-control helper
retains system button layout and chooses OnAccent/OnRecording labels for contrast.
No navigation, tab, list, sheet or AR lifecycle is replaced. Existing fixed export
palette constants remain independent of appearance, and exporter source is unchanged.

Add a color by adding all four variants to Colors.xcassets and a ColorToken case;
add its supported foreground/background pairs to contrast tests. Use semantic
system-font tokens, never fixed text sizes. Add future reusable styles beside
AppTheme; evolve liquidGlass instead of adding another material stack. S2 components
and S3 remaining-view migration are pending. S0 inventory below is historical.
Apple builds, resolved-color Swift tests and visual checks remain unverified.
Source snapshot: UI redesign Phase 0 commit `268505c`. S0 changes documentation only.
Reuse `UI/AppTheme.swift` and its liquidGlass modifiers; there is no second theme.
The intended destination is `RoomScanner/DesignSystem/`, shared by both targets.
Lexical counts below are candidates, not AST findings or approved exceptions. They
include platform/3D colors; comments/strings and multiline variants may affect matching.
| Pattern | Occurrences | Files |
|---|---:|---:|
| RGB Color literals | 6 | 2 |
| Named color candidates | 86 | 37 |
| Fixed system font sizes | 9 | 7 |
| Literal corner radii | 31 | 14 |
| Literal padding | 82 | 23 |
| Material backgrounds/fills | 41 | 15 |
| Button styles | 59 | 26 |
| Tint modifiers | 11 | 11 |
| Root blue tint | 8 | 8 |
| Shadows | 3 | 3 |
| Animations | 2 | 2 |

Blue count includes one root `.tint(.blue)` (`UI/RootView.swift:36`) and seven
per-view overrides. `AccentColor.colorset` currently defines one universal yellow
(#facc15 approximately), without dark or high-contrast variants. `AppTheme` duplicates
that fixed RGB palette in SwiftUI, CGColor and platform colors. This conflicts with
forced blue and cannot yet provide contextual contrast. S1 must keep brand yellow
as a fill with dark OnBrand, select contrast-tested link/icon Accent variants, and
remove per-view overrides. No color/contrast correction has been applied in S0.

### Classification before migration
- UI candidates: statuses, recording controls, cards, badges, lists, inspectors,
  photo controls and toolbars should use semantic tokens/styles. Native buttonStyle
  usage is legitimate; centralization should preserve native controls and actions.
- Icon sizes: seven of the nine fixed-font candidates appear to size glyphs; retain
  centrally named icon-size tokens after context review. The two Plan2DView text
  labels (lines 58/75) need separate Dynamic Type/plan-overlay review. No blanket
  exemption for every fixed font is approved.
- SceneKit/RealityKit/ARKit: mesh materials, marker textures, confidence colors and
  native overlay geometry can legitimately need platform color/geometry values.
  Examples: Viewer/AnnotationIcon, TechnicalRoom/Capture/TechnicalRoomScanCoordinator,
  HouseRadiators/Capture/HouseRadiatorScanCoordinator and SceneEditing/StudioEngineering.
  Review individual render expressions; surrounding SwiftUI HUDs are not exempt.
- Exports: Export/PlanRenderer, SVGExporter, DXFExporter and TechnicalMeshExporter
  have fixed drawing/format colors. PlanSceneBuilder also consumes plan textures.
  Preserve their output bytes/palettes independently of UI appearance. Future
  ExportPalette must not depend on SwiftUI or dynamic theme assets. Raw CGColor
  literals are intentionally outside the SwiftUI Color(red:) count.
- Existing AppTheme material/shadow implementations are centralization candidates.
  Do not add new material layers or custom navigation chrome. S2 evolves these
  existing modifiers; S0 has not changed their appearance.
- Motion review: Plan2DView animation and ScanPhotoButton feedback are the two
  explicit animation calls found. Both require Reduce Motion review.

### Files containing matches
Paths below are relative to `RoomScanner/`. Category counts are per file and may
overlap. Blue is included in Tint; Color also includes render-only candidates.
| File | Categories (occurrences) |
|---|---|
| `HouseRadiators/Capture/HouseRadiatorScanCoordinator.swift` | Color:1, Radius:1, Padding:1, Material:1 |
| `HouseRadiators/Capture/HouseRadiatorScanView.swift` | Color:2, Button:2, Tint:1, Blue:1 |
| `HouseRadiators/HouseRadiatorViews.swift` | Color:3, Tint:1, Blue:1 |
| `MacUI/MacRootView.swift` | Radius:2, Padding:2 |
| `MacUI/OrganisedExportSheet.swift` | Font:1, Button:2 |
| `Notes/ProjectVoiceNotesView.swift` | Color:1, Padding:1, Button:1, Tint:1 |
| `Notes/VoiceNotePlayerSheet.swift` | Color:2, Button:2, Tint:1 |
| `Scan/CapturePins.swift` | Color:3 |
| `Scan/HoldMicrophoneControl.swift` | Color:1 |
| `Scan/LiveScanNotes.swift` | Color:1, Radius:1, Padding:3, Material:5 |
| `Scan/RoomCaptureViewRepresentable.swift` | Color:1 |
| `Scan/ScanRelocalizationProbe.swift` | Color:1, Radius:1, Material:1 |
| `Scan/ScanSaveStatus.swift` | Color:1, Padding:1, Material:1 |
| `Scan/ScanView.swift` | Color:2, Radius:4, Padding:5, Material:3, Button:4 |
| `Scan/TechnicalRoomScanView.swift` | Color:8, Radius:2, Padding:4, Material:4, Button:4, Tint:1, Blue:1, Shadow:1 |
| `SceneEditing/StudioEditorView.swift` | RGB:1, Color:4, Font:2, Radius:9, Padding:33, Material:13, Button:8, Tint:1, Blue:1, Shadow:1 |
| `SceneEditing/StudioEngineering.swift` | Color:1 |
| `SceneEditing/StudioLibraryView.swift` | Color:1, Button:1, Tint:1, Blue:1 |
| `SceneEditing/StudioTechnicalData.swift` | Color:1 |
| `TechnicalRoom/Capture/TechnicalRoomScanCoordinator.swift` | Color:3 |
| `TechnicalRoom/TechnicalAnnotationEditor.swift` | Color:4 |
| `TechnicalRoom/TechnicalGoogleAIAccount.swift` | Button:1 |
| `TechnicalRoom/TechnicalMEPReviewView.swift` | Color:1, Padding:1, Button:1 |
| `TechnicalRoom/TechnicalRoomLibraryView.swift` | Color:3, Radius:1, Padding:2, Button:1, Tint:1, Blue:1 |
| `TechnicalRoom/TechnicalSavedScanView.swift` | Color:1, Padding:4, Material:2, Button:6 |
| `TechnicalRoom/TechnicalSurveyPhotoView.swift` | Color:1, Button:1 |
| `UI/AppTheme.swift` | RGB:5, Color:1, Material:2, Shadow:1 |
| `UI/ExportSheet.swift` | Color:2, Material:1, Button:1 |
| `UI/HouseDetailView.swift` | Radius:1, Padding:3, Material:1, Button:1 |
| `UI/HousePhotosTabView.swift` | Radius:1, Button:1 |
| `UI/Plan2DView.swift` | Color:12, Font:2, Padding:1, Material:2, Button:4, Motion:1 |
| `UI/Projects/ProjectPinsView.swift` | Color:1 |
| `UI/Projects/ProjectPrivacyView.swift` | Color:1 |
| `UI/Projects/ProjectQuantitiesView.swift` | Color:1 |
| `UI/Projects/ProjectScanPreview.swift` | Color:1, Button:1 |
| `UI/Projects/ProjectVerificationView.swift` | Color:1 |
| `UI/Projects/RenovationNavigation.swift` | Font:1, Radius:3, Padding:3, Button:4 |
| `UI/Projects/UnfinishedScansView.swift` | Padding:1, Button:1 |
| `UI/RoomDetailView.swift` | Color:2, Padding:2, Material:1 |
| `UI/RoomListView.swift` | Color:1, Font:1, Radius:3, Padding:1, Button:4, Tint:1, Blue:1 |
| `UI/RootView.swift` | Color:1, Font:1, Padding:2, Button:1, Tint:1, Blue:1 |
| `UI/ScanPhotoButton.swift` | Color:5, Padding:1, Button:1, Tint:1, Motion:1 |
| `UI/SettingsView.swift` | Font:1, Padding:2 |
| `UI/SurveyPhotoGallery.swift` | Padding:2, Button:3 |
| `Viewer/AnnotationIcon.swift` | Color:6 |
| `Viewer/ViewerControls.swift` | Radius:1, Padding:3, Material:1, Button:1 |
| `Viewer/ViewerView.swift` | Color:4, Radius:1, Padding:4, Material:3, Button:2 |

S0 verification: inventory actually generated from tracked Swift source; no app
rendering, contrast resolution, Apple build or Dynamic Type check occurred. No
production line changes, removed component or dependency in S0. S1–S4 are pending;
no app-wide token migration or visual quality claim is made. Physical checks are
listed in `docs/DEVICE_TEST_CHECKLIST.md` as device validation pending.
