# iPhone and iPad UI refinement

## Phase 0 · Screenshot baseline

The baseline covers the Projects grid, project dashboard, House scan setup sheet, and design-system gallery. Each device shows the same Lindenhof project with the two saved room scans from `DemoDataTests`. Each screen has an English light-mode and German dark-mode capture, for 16 PNGs across iPhone and iPad.

| Screen | Issue | Proposed fix | Category | Approval status | Files | Verification | Test result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Projects, dashboard, scan setup, gallery | Missing comparable simulator images | Open existing destinations in a Debug simulator with a seeded catalogue | Phase 0 tooling | Approved for local implementation | `RenovationNavigation.swift`, `ScreenshotDestination.swift`, `DemoDataTests.swift` | Review 16 PNGs with the source commit and device metadata in the manifest | Apple builds, hosted fixture test and visuals UNVERIFIED |

### Capture on a Mac

From the repository root, with Xcode selected, XcodeGen and Node installed, run:

```sh
node Scripts/capture_ui_screenshots.mjs
```

Install an iOS 18 or later simulator runtime with an iPhone and iPad available in Xcode. The script creates temporary devices from those models, runs the hosted fixture test, and waits for the requested screen before taking each screenshot. The printed directory under `build/ui-screenshots/` contains the PNGs and a manifest recording the commit, working tree, Xcode version, model, runtime, language, appearance, and image dimensions. Use the same simulator models and runtime for before/after comparison.

The manual **Pull request tests** workflow has a **Capture the iPhone and iPad visual baseline after tests pass** option. It uploads the images after both Apple schemes and the service checks pass. This local implementation has no CI run URL or rendered screenshots yet. If a Mac runner is unavailable, matching device screenshots can support visual review. Motion and capture responsiveness require separate interaction checks. Camera and LiDAR device validation pending.

## Shared iPhone and iPad styling

The existing palette pairs brand yellow (`#FACC15`) with charcoal ink (`#111110`). The semantic action accent resolves to dark ochre in standard light appearance and yellow in dark appearance. The shared components use these existing assets and system text styles.

The project dashboard emphasizes the quantities surveyors need to compare at a glance. Its short overview and drill-down action follow a pattern also documented in [magicplan’s project dashboard guide](https://help.magicplan.app/the-new-magicplan). dWalkScan keeps its existing scan-total labels, overlap explanation, project navigation and measurement formatting.

| Screen | Issue | Implemented fix | Category | Approval status | Files | Verification | Test result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Projects, House, Technik, Studio libraries | Grid and card rules were repeated. Compact grids retained two columns at accessibility text sizes. | Share grid sizing, card surfaces and 120 ms press feedback. Accessibility sizes use full-width cards. Reduce Motion uses immediate feedback. | A | No approval required | `DS.swift`, `DSComponents.swift`, `RenovationNavigation.swift`, `ProjectScanLibraryView.swift` | Check long names, large text and pressed states on a device | Swift grid regression added to `DesignSystemTests.swift`; Apple run pending |
| Project dashboard | Statistics used fixed-width columns and the section action had a text-sized target. | Share a scalable statistics grid, measurement typography and a section header with a 44-point action. VoiceOver receives a separate label and value. | A | No approval required | `DS.swift`, `DSComponents.swift`, `ProjectDashboardView.swift` | Compare the overview in both languages, at large text sizes and with VoiceOver | Visual and interaction results UNVERIFIED |
| Debug design-system gallery | Library styles and localized measurements were hard to compare in isolation. | Show the library card, press feedback and statistics grid alongside language, appearance and text-size controls. | A | No approval required | `DesignSystemGallery.swift` | Review the gallery on iPhone and iPad | Rendered result UNVERIFIED |
