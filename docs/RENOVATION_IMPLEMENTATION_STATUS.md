# Renovation workspace — implementation and validation record

Working branch: `codex/renovation-projects`.
Worktree: `.worktrees/renovation-projects`.

The original checkout was not edited by this implementation. During this work it
advanced independently to `feat/v1.3`, incorporating the first phase commits through
`f9cfe68`. Remaining integration fixes and the organised ZIP feature live on this
branch. Review/merge these changes into the intended release branch before building
that release. Nothing was pushed by this task.

## Phase results and changed files

All paths below are relative to the repository. Follow-up fixes accompany the
individual phase commits; no new dependency, StoreKit integration or IFC work was
introduced. Original `.roomscan`, `.housescan`, `.technicalroom` and Technical Room
v1 schemas remain unchanged. Capture implementation is retained; scan-side changes
are language/presentation lookups and Pro-details visibility only.

| Phase | Implemented / planned | Principal files |
| --- | --- | --- |
| 1 | Additive project index, typed library references, idempotent Unsorted reconciliation, optional notes/pins/checks. Coordinated updates read the latest index. | `Domain/Projects/ProjectIndex.swift`, `ProjectLibraryEntry.swift`, `Storage/ProjectIndexStore.swift`, `UI/Projects/RenovationWorkspace.swift` |
| 2 | Home / Projects / Design / Search; Settings profile action; persistent current-project Scan; onboarding/coaching; project covers; source preview segments for floor plan, 3D, measure and photos; direct Design routes; rename aliases, duplicate, share and reassignment menus. | `UI/RootView.swift`, `UI/Projects/RenovationNavigation.swift`, `ProjectScanPreview.swift`; room/house/technical detail labels; `SceneEditing/StudioEditorView.swift`, `StudioLibraryView.swift` |
| 3 | System / English / Deutsch preference at app root, German catalogue, localized number formatting and readable DXF layer names, localized CSV/report/share labels, en/de camera usage descriptions. | `Domain/Projects/AppLanguage.swift`, `Resources/Localizable.xcstrings`, `Resources/{en,de}.lproj/InfoPlist.strings`, `App/RoomScannerApp.swift`, `UI/SettingsView.swift`, `Domain/Measurements.swift`, export/readme/name helpers, `project.yml` |
| 4 | Pro details is a presentation preference. DN/port controls, detailed capture evidence, structured JSON access and planning references are gated; saved fields are retained. Validation warnings stay visible. | `UI/SettingsView.swift`, `UI/ExportSheet.swift`, `TechnicalRoom/TechnicalAnnotationEditor.swift`, `TechnicalRoomLibraryView.swift`, `SceneEditing/StudioTechnicalData.swift`, `Scan/TechnicalRoomScanView.swift` |
| 5 | Project PDF: cover, available level plans, room/quantity schedules, notes, pin maps/legends, selected user photos and unresolved-items pages. | `Domain/Projects/ProjectReport.swift`, `Storage/ProjectReportLoader.swift`, `Export/Projects/ProjectReportRenderer.swift`, `UI/Projects/ProjectDeliverablesView.swift` |
| 6 | Floor/project survey quantities, wall net area clipped to hosts and unioned openings, projected ceiling area, volume range, counts, configurable waste allowance, PDF/CSV schedules. | `Domain/Projects/RenovationQuantities.swift`, `Export/Projects/ProjectQuantitiesCSV.swift`, `UI/Projects/ProjectQuantitiesView.swift` |
| 7 | Plan task pins, status, photo reference, optional element link; explicit renovation-tag edits reuse existing Design phase records. | `Domain/Projects/ProjectPin.swift`, `UI/Projects/ProjectPinsView.swift`, report/index extensions |
| 8 | One-file-per-level ZIPs for DXF/SVG/parametric meshes; known floor elevations used for DXF/mesh; native share/drag types; organised project and photo-only ZIPs. | `Export/Projects/LevelExportService.swift`, `ProjectBundleExporter.swift`, `SurveyPhotoArchiveWriter.swift`, `Export/ExportService.swift`, `ExportSubject.swift`, `UI/ExportSheet.swift`, `MacUI/DragExportProvider.swift` |
| 9 | Plan only: manual sketch first, optional later mesh-free AR support. | `docs/MANUAL_ROOM_MODE_PLAN.md` |
| 10 | Known-distance check tied to a source dimension; reference/observed values, absolute/signed error, method/date, report notes. No scale correction or global accuracy rating. | `Domain/Projects/ProjectDistanceCheck.swift`, `UI/Projects/ProjectVerificationView.swift`, report/index extensions |
| 11 | New-user local default; preserve discovery of existing cloud content; no automatic package migration. Explicit AI enabling consent, per-send confirmation retained, visible off switch. Scoped deletion with connected-root preflight and protection of shared source dependencies. Required-reason manifest. | `Storage/CloudAvailability.swift`, `RoomStore.swift`, `ProjectPrivacyStore.swift`, `UI/Projects/ProjectPrivacyView.swift`, Google account/review views, `Resources/PrivacyInfo.xcprivacy`, `docs/RENOVATION_PRIVACY_REVIEW.md` |
| 12 | Plan only: independently aligned before/after captures and reviewed matches. | `docs/RESCAN_COMPARISON_PLAN.md` |
| 13 | Plan only: injected future feature-access decisions; no paid restrictions. | `docs/ENTITLEMENT_ABSTRACTION_PLAN.md` |

## Organised ZIPs and photo names

From a project, open **Project report and exports**, then **Everything · organised
ZIP** or **Photos · ZIP**. The room/house export sheet also offers **Photos · ZIP**;
its existing Everything ZIP now separates plans, models, data and numbered photos.

Example complete project archive:

```text
Flat/
  README.txt
  manifest.json
  project-index.json
  Reports/project-report.pdf
  Quantities/quantities.csv
  Notes/project-notes.txt
  Photos/
    Kitchen.1/Kitchen.1.jpg
    Kitchen.1/camera.json
    Kitchen.2/Kitchen.2.jpg
    Kitchen.2/camera.json
    Bathroom.1/Bathroom.1.jpg
    Bathroom.1/camera.json
  Scans/<name-kind-id-library>/
    Original/<uuid>.roomscan/  # or .housescan / .technicalroom
    Plans/
    Models/
    Data/
  Designs/<name-kind-id-library>/
    editable-design.json
    engineering-register.csv
    floor-plans.pdf
    Models/level-0.usdz
    Models/level-0.obj-with-materials.zip
```

Photo numbering starts at 1 in each room. A room revisited continues its sequence.
Same-name rooms or copied scan IDs receive a folder suffix (`Kitchen.1-2`); the
photo index retains source reference, room ID, photo ID and original number.
Names are normalized and sanitized for Windows, including reserved names and
trailing dots. Exported camera metadata uses correct relative image paths,
original and optional display poses, timestamps, and device-validation status.
It is an export envelope, not a modification of capture schemas. Unmarked automatic
camera evidence remains in the original technical package; Photos contains user
survey photos. No QR/public links or passwords are generated.

Available outputs are generated independently. Missing geometry and failed outputs
are recorded in `manifest.json` and the README, never replaced by invented models.
Photo-only export fails visibly if a referenced scan is missing. Original-package
copying rejects symlinks and has a 2 GiB cumulative copy budget. Report photo loading
is bounded to 100 / 64 MiB; exceeding that is listed in the PDF. ZIP photo folders
retain available user photos independently of the PDF display budget. Level OBJ
with materials remains a nested ZIP so its material files stay together. Windows
extraction should use a short destination such as `C:\Scans` for deeply nested
original packages.

## Validation actually performed here

Host: Windows. No connected iPhone or Mac. **No Xcode compilation, Swift unit tests,
UI tests, simulator screenshots or device tests have run.** No phase is represented
as built or device-validated.

- `git diff --check`: checked during implementation.
- `node Scripts/audit_localization.js --strict`: checked fixed UI literals and
  explicit text/format lookups against the catalogue; 1,000 keys at the validation
  checkpoint, no missing German values or uncovered static literals in that audit.
- Independent Python standard-library check: catalogue JSON parsed; German format
  placeholders match English; privacy plist parsed; all new project Domain files
  import Foundation only.
- `xcodegen generate`: attempted, unavailable (`xcodegen` not found).
- `xcodebuild test` for **RoomScannerMac** and **RoomScanner**: both attempted,
  unavailable (`xcodebuild` not found). They remain **unrun**.
- YAML parser was unavailable on Windows; project generation remains unverified.

## Tests added or updated (all Swift tests unrun)

- `ProjectIndexTests`: round-trip, legacy discovery/idempotence, missing/offline
  references, reassignment, source bytes unchanged, latest-index coordinated updates.
- `LocalizationCoverageTests`: every catalogue key has German text and matching
  format tokens; German decimal comma.
- `ProjectReportTests`: PDF structure/page count.
- `RenovationQuantitiesTests`: duplicate openings subtract once, unchanged net
  room dimensions, volume bounds/waste, CSV formula protection and locale.
- `ProjectPinTests`: source coordinates, Codable, reference validation, pins follow
  reassignment to another project.
- `LevelExportTests`: known floor elevations, no invented missing height, level ZIP naming.
- `ProjectDistanceCheckTests`: actual error math, zero-length rejection, pending status.
- `ProjectPrivacyTests`: source dependency protection, offline-root rejection,
  selected deletion scope, unrelated files preserved, stale catalogue rejection.
- `PhotoArchiveTests`: room.number naming, per-room 1s, case/unsafe-name collisions,
  paths and camera metadata; staged complete bundle includes original package,
  numbered photos/report/CSV and leaves source plan bytes unchanged.
- Existing archive path expectations, cloud-default tests and locale-sensitive
  export assertions updated for the intentional behaviours.

## Mac validation

Run in the worktree/merged branch with Xcode and XcodeGen installed:

```sh
xcodegen generate
xcodebuild test -project RoomScanner.xcodeproj -scheme RoomScannerMac -destination 'platform=macOS'
xcrun simctl list devices available
xcodebuild test -project RoomScanner.xcodeproj -scheme RoomScanner -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Choose an installed iPhone simulator if that name is unavailable. Both app targets
must compile and all existing/new tests must pass before release. Inspect warnings,
archive manifests/resources and the generated privacy report. Review exported PDF
pages in Preview and extract ZIPs on Windows to check names/content/relative paths.

If continuing from the independently updated `feat/v1.3` checkout, review and merge
the latest implementation branch before running those commands:

```sh
git status --short
git merge --no-ff codex/renovation-projects
```

Do not run that merge with unrelated uncommitted work. The branch intentionally
does not overwrite the main checkout's README or `.gitignore` changes. Resolve any
later overlapping changes by preserving the corresponding user edits.

## Device and release checklist — device validation pending

1. Upgrade an existing local and an existing iCloud library. Confirm scans are
   referenced in Unsorted and package bytes/locations are unchanged. Repeat launch.
2. Create a project, scan each source type, cancel, save, import, rename, duplicate
   and move items between projects. Open Design from preview, rows and detail screens.
   Check refresh after saving a design and after deleting a project from Settings.
3. Check iPhone/iPad portrait/landscape, accessibility text sizes, VoiceOver, Dark
   Mode, keyboard entry, back navigation and native scan accessory with both SDK paths.
4. Switch System/English/Deutsch while screens and sheets are open. Inspect dates,
   decimal commas, mm/m/m², PDF, CSV, readable DXF layers and sharing labels.
5. Take A1/B1/A2 photos, save/reopen/export. Check camera direction, gallery,
   fullscreen, per-room names and matching IDs in both ZIP manifests. Test unsafe,
   Unicode, duplicate and case-only room names on Windows extraction.
6. Place pins in asymmetric rooms and on different levels; link photos/elements,
   change status/renovation tag, reopen and inspect Design and PDF legends. Check
   crowded maps, long notes, missing sources, repeated scans and PDF photo-budget warnings.
7. Verify quantities against independent fixture calculations and a real survey.
   Sloping ceilings are not measured surfaces; volume is a range. Test overlapping
   openings, unknown hosts and partial/missing floor polygons. No heat-load,
   cooling-load, material U-value or ventilation engineering calculation is added.
8. Export every available format and multi-level archive; open DXF/SVG/meshes in
   external readers. Confirm independent storey positions and README local-datum
   warnings. Revit/IFC validation is outside these phases.
9. Record five pipe length references and three equipment width/depth/height
   references, repeated three times. Check three alignment points before and after
   interruption/relocalisation. Do not convert these into a universal accuracy claim.
10. Confirm Google stays off without consent, every send names its endpoint, off
    cancels new processing, and depth is not included in image submissions. Check
    account sign-out, backend retention and data-collection declarations separately.
11. Test project deletion on a disposable library: offline cloud preflight,
    references needed by another design, partial filesystem failure, shared copies,
    unchanged unrelated files and no stale-window resurrection.

## Explicit limits and assumptions

- Catalogue coverage is static. Runtime error messages from SDKs, diagnostic string
  assembly, interpolated legacy labels and generated enum titles need a bilingual
  device pass; static coverage is not proof every runtime sentence is translated.
- Metadata-only Rename in the new project browser is a project alias; it does not
  rewrite original package metadata. The existing detail Rename remains explicit.
- A project can contain independent overlapping/repeated scans. Its quantity sum
  is labelled a sum of surveys, not a deduplicated building total. Primary-plan area
  is shown separately. Technical captures without a retained dimensioned shell do
  not gain an invented floor plan, room area or room volume.
- No new engineering accuracy, recognition capability or DIN compliance is claimed.
  Existing `accuracyMm: null` values and original survey formats stay unchanged.
- This implementation needs Mac build review and on-device testing before it is
  suitable for a client handoff. See the privacy review for additional release gates.
