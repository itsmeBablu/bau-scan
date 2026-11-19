# Protected Features & Branding Reference

This document defines the strictly protected identity, assets, design system, and custom functionality for **dWalkScan** (`https://github.com/itsmeBablu/d-walk-scan`).

When synchronizing, merging, or cherry-picking code from the upstream repository (`https://github.com/vincentlauriat/3DScanner`), the items in this list **must NEVER be overwritten, replaced, or reverted** to upstream values.

---

## 1. Identity & Authorship

| Element | dWalkScan (Keep Local) | Upstream (Never Accept) |
| :--- | :--- | :--- |
| **Owner / Author** | `BabuReddy` / `itsmeBablu` | `Vincent Lauriat` / `vincentlauriat` |
| **App Name** | `dWalkScan` | `3DScanner` / `RoomScanner` |
| **Repository URL** | `https://github.com/itsmeBablu/d-walk-scan` | `https://github.com/vincentlauriat/3DScanner` |
| **Documentation / Website** | Do NOT redirect to external project website; link to git repo only | `https://vincentlauriat.github.io/3DScanner` |
| **Bundle ID** | `io.github.itsmebablu.dwalkscan` | `io.github.vincentlauriat.3dscanner` |
| **iCloud Container** | `iCloud.io.github.itsmebablu.dwalkscan` | `iCloud.io.github.vincentlauriat.3dscanner` |
| **UTTypes / Uniform Type Identifiers** | `io.github.itsmebablu.dwalkscan.room`, `io.github.itsmebablu.dwalkscan.house` | `io.github.vincentlauriat.3dscanner.*` |

---

## 2. Branding Assets & Icons

Do not accept upstream modifications or replacements for any of the following asset files:

1. **Vector Logo**:
   - `RoomScanner/Resources/ibv.svg`
   - `docs/assets/ibv.svg`
   - `docs/ibv.svg`
2. **Asset Catalogs**:
   - `RoomScanner/Resources/Assets.xcassets/AppLogo.imageset/` (Contains vector SVG + 1x, 2x, 3x rendered icons)
   - `RoomScanner/Resources/Assets.xcassets/AppIcon.appiconset/` (Generated from `ibv.svg` for iOS 1024x1024 and macOS all scales)
   - `RoomScanner/Resources/Assets.xcassets/AccentColor.colorset/` (Set to `#facc15`)

---

## 3. UI Color Palette & Liquid Glass Styling

The UI is built on a custom brand theme and Apple device liquid glass materials. Do not revert or overwrite:

- **`RoomScanner/UI/AppTheme.swift`**:
  - `primaryYellow`: `#facc15` (Main brand color, highlights, 3D dimension lines, active tabs)
  - `secondaryYellow`: `#fef08a` (Secondary accents, badges)
  - `softBackgroundTint`: `#fef3c7` (Subtle warm yellow tint for surfaces and card highlights)
  - `darkCharcoal`: `#111110` (Main text, 3D viewport canvas background, deep contrast)
  - `deepWarmCharcoal`: `#272000` (Secondary warm charcoal for labels and borders)
- **Modifiers**:
  - `.liquidGlass(cornerRadius:interactive:)` using `.ultraThinMaterial` / `.thinMaterial` with specular reflection highlight and subtle drop shadow.
  - `.liquidGlassCard(...)` for cards, lists, and floating HUD containers.
  - `BrandLogoView` for header and navigation bar branding.
- **Affected UI Views**:
  - `RoomScanner/Viewer/ViewerView.swift` (Canvas background `#111110`)
  - `RoomScanner/Viewer/ViewerControls.swift` (Floating pill with `.liquidGlass()`)
  - `RoomScanner/UI/RoomDetailView.swift` & `HouseDetailView.swift` (Liquid glass tab bars and brand headers)
  - `RoomScanner/UI/RoomListView.swift` (Liquid glass cards and empty state)
  - `RoomScanner/Viewer/PlanSceneBuilder.swift` (Primary yellow dimension indicators `#facc15`)

---

## 4. Measurement Engine (mm & Meters)

The local app supports user-configurable measurements with support for millimeters, meters, and dual display:

- **`RoomScanner/Domain/Measurements.swift`**:
  - `MeasurementUnit` enum (`.millimeters`, `.meters`, `.both`)
  - `MeasurementFormat.millimeters(meters:fractionDigits:)`
  - `MeasurementFormat.length(meters:unit:locale:fractionDigits:)`
- **Settings Picker**:
  - `@AppStorage("measurementUnit")` in `RoomScanner/UI/SettingsView.swift`
- **Export & Render Engine Units**:
  - `RoomScanner/Export/PlanRenderer.swift` (Respects user's mm / meters choice)
  - `RoomScanner/Export/SVGExporter.swift` (Exports accurate mm dimensions with unit annotations)
  - `RoomScanner/Export/DXFExporter.swift` (Millimeter-accurate CAD dimensions)

---

## 5. Protected Configuration & Documentation Files

Never overwrite wholesale from upstream:
- `project.yml`
- `RoomScanner/Info-iOS.plist`
- `RoomScanner/Info-macOS.plist`
- `RoomScanner/RoomScanner-iOS.entitlements`
- `RoomScanner/RoomScanner-macOS.entitlements`
- `RoomScanner/RoomScanner-macOS-Release.entitlements`
- `RoomScanner/Resources/Localizable.xcstrings`
- `README.md`
- `ARCHITECTURE.md`
- `docs/index.html`
- `docs/monograph.json`
- `appcast.xml`
- `release/`
- `.github/workflows/ios-unsigned.yml`
- `Scripts/release.sh`
- `Scripts/make-dmg-background.swift`
