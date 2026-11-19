<p align="center">
  <img src="docs/assets/ibv.svg" width="96" height="96" alt="dWalkScan bau-scan logo" />
</p>

<h1 align="center">dWalkScan (bau-scan)</h1>

<p align="center">
  <strong>LiDAR Room & House 3D Scanner with Precision Architectural 2D Floor Plans</strong>
</p>

<p align="center">
  <a href="https://github.com/itsmeBablu/bau-scan/releases"><img src="https://img.shields.io/badge/Release-v1.0.0-facc15.svg?style=flat-square&labelColor=111110" alt="Release"></a>
  <a href="https://developer.apple.com/ios/"><img src="https://img.shields.io/badge/iOS-18.0%2B-blue.svg?style=flat-square" alt="iOS 18.0+"></a>
  <a href="https://developer.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-15.0%2B-blue.svg?style=flat-square" alt="macOS 15.0+"></a>
  <a href="https://developer.apple.com/augmented-reality/roomplan/"><img src="https://img.shields.io/badge/LiDAR-Apple%20RoomPlan-brightgreen.svg?style=flat-square" alt="Apple RoomPlan"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-gray.svg?style=flat-square" alt="License MIT"></a>
</p>

---

Scan the rooms of your house with your iPhone's **LiDAR** sensor, generate **architecturally dimensioned 2D floor plans** and **3D models**, and export them directly to any 2D application (**PDF**, **SVG**, **DXF / CAD**) or 3D workflow (**USDZ**, **OBJ**, **STL**, **PLY**).

A companion **Mac application** (sharing the exact same Swift codebase) displays plans, 3D models, and measurements on your desktop, with drag-and-drop support, printing, and automated exports. **iCloud Drive** keeps iPhone and Mac continuously in sync, maintaining a dedicated `dWalkScan` directory in Files and Finder.

> [!NOTE]
> **Status:** **v1.0.0 Released** — [Download the Mac App](https://github.com/itsmeBablu/bau-scan/releases/latest) (notarized DMG with Sparkle auto-updates).  
> **iOS Distribution:** Build and run via Xcode (`⌘R`) or sideload the unsigned IPA via Sideloadly / GitHub Actions on Windows.

---

## Key Features

### 📐 Architectural 2D Plans & Annotations
* **Opening Dimension Lines (DIN Standard):** Opening width positioned **above** the dimension line, height positioned **below**, terminating with architectural diagonal oblique ticks (`/`).
* **Window Parapet Height (`BRH`):** Clear window sill / parapet height (`BRH: <height>`) centered along the interior sill with **zero text overlap**.
* **Interior Room Badges:** Centered at `Polygon2D.interiorPoint` with bold room titles and calculated $\text{m}^2$ area inside translucent badges with Primary Yellow (`#facc15`) borders.
* **Selectable Units:** Support for millimeters (`mm`), meters (`m`), or dual format (`mm & m`), with standard English dot-decimal notation (`.`).
* **2D Export Suite:** Vector SVG with CAD-style layers (`walls`, `doors`, `windows`, `dimensions`, `text`), DXF R12, scaled PDF (A4 landscape), and high-resolution PNG.

### 🧊 3D Scanning & RealityKit Viewer
* **Apple RoomPlan LiDAR Capture:** Real-time guided capture with surface recognition, door/window detection, and coaching indicators.
* **Interactive Viewer:** 3D orbit viewer, top-down 2D orthographic plan, and real-world AR tabletop placement (1:20 / 1:50 scale) or 1:1 overlay.
* **3D Export Formats:** USDZ (native parametric scene or raw scan mesh), OBJ, STL, and PLY.

### 🎨 Design System & Liquid Glass
* **Custom Brand Palette:**
  * **Primary Yellow:** `#facc15` (Brand focus, dimension accents, and active states).
  * **Secondary Yellow:** `#fef08a` / `#fef3c7` (Badge surfaces and subtle highlights).
  * **Dark Charcoal:** `#111110` / `#272000` (High-contrast typography and CAD walls).
* **Native Liquid Glass:** Blur-backed cards (`.liquidGlass()` and `.liquidGlassCard()`) tailored for iOS 18+ and macOS 15+.

---

## Feature Matrix

| Feature | Status | Technology / Notes |
|---|---|---|
| **LiDAR Room Capture** | ✅ Built | Apple `RoomCaptureView`, real-time coaching |
| **Architectural 2D Plan** | ✅ Built | Core Graphics, diagonal ticks, top width, bottom height, `BRH:` sill height |
| **Room Badges & Area** | ✅ Built | Centered at `interiorPoint`, bold title + $\text{m}^2$ calculation |
| **Units: mm & meters** | ✅ Built | Configurable `mm`, `m`, `both` with English dot-decimal (`.`) standard |
| **Interactive 3D / AR Viewer** | ✅ Built | SwiftUI `RealityView`, orbit controls, 1:20 / 1:50 AR tabletop scale |
| **Detailed Measurements** | ✅ Built | Area, perimeter, ceiling height range, doors, windows, objects |
| **2D Exports** | ✅ Built | PDF (A4 Landscape), PNG, SVG (layered), DXF R12 |
| **3D Exports** | ✅ Built | USDZ, OBJ, STL, PLY (plan mesh + raw scan mesh) |
| **Mac Companion App** | ✅ Built | SwiftUI macOS 15+, split view, drag & drop, printing (⌘P) |
| **iCloud Drive Sync** | ✅ Built | Multi-device sync, `.roomscan` packages, conflict-safe |
| **Multi-Room House Merge** | 🚧 v2 | `StructureBuilder`, multi-story floor alignment, `.housescan` packages |

---

## Requirements

* **iOS:** iPhone **Pro** model with LiDAR (iPhone 12 Pro through 17 Pro), running **iOS 18.0+**.
* **macOS:** Mac with Apple Silicon or Intel running **macOS 15.0+**.
* **Development Environment:** Xcode 16+ or 27 with `xcodegen` (`brew install xcodegen`).
* **iCloud:** Apple Account signed in on devices for automatic synchronization (local storage used as fallback).

---

## Build & Development

The Xcode project is generated deterministically using [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
# 1. Generate the Xcode project file
xcodegen generate

# 2. Build and run unit tests for iOS Simulator
xcodebuild -scheme RoomScanner \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO build test

# 3. Build and test the macOS companion app
xcodebuild -scheme RoomScannerMac \
  -destination 'platform=macOS' build test
```

---

## Sideloading on Windows (No Mac Required)

You can build and test **dWalkScan** on your physical iPhone directly from Windows using GitHub Actions and Sideloadly:

<details>
<summary><strong>Click to expand step-by-step Windows sideloading guide</strong></summary>

### 1. Build the Unsigned IPA on GitHub Actions
1. Navigate to your repository's **Actions** tab on GitHub.
2. Select the **Build unsigned iPhone IPA** workflow from the left sidebar.
3. Click **Run workflow**, choose `main`, and confirm.
4. When the build finishes, scroll down to **Artifacts** and download **`dWalkScan-local-unsigned-ipa.zip`**.
5. Extract the ZIP archive on Windows to obtain `dWalkScan-local-unsigned.ipa`.

### 2. Install Sideloadly & Prerequisites
1. Download and install **iTunes** and **iCloud** for Windows using the standalone desktop web installers (avoid the Microsoft Store versions).
2. Download and install [Sideloadly](https://sideloadly.io/).

### 3. Sign & Install onto iPhone
1. Connect your unlocked iPhone to your PC via USB.
2. When prompted on the iPhone, select **Trust This Computer** and enter your passcode.
3. Open Sideloadly; verify your connected iPhone appears in the device dropdown.
4. Drag `dWalkScan-local-unsigned.ipa` into Sideloadly.
5. Enter your free Apple Account email and click **Start**.
6. On the iPhone, go to **Settings → General → VPN & Device Management**, tap your developer certificate, and tap **Trust**.
7. If iOS 16+, enable **Settings → Privacy & Security → Developer Mode** and reboot when prompted.
8. Launch **dWalkScan**, grant camera/LiDAR permissions, and begin scanning!

</details>

---

## Repository Structure

```
d-walk-scan/
├── RoomScanner/             # Shared SwiftUI source (iOS 18+ & macOS 15+)
│   ├── App/                 # App lifecycle and root routing
│   ├── Domain/              # Geometry, FloorPlan model, and Measurements formatters
│   ├── Export/              # PlanRenderer, SVGExporter, DXFExporter, MeshWriters
│   ├── Scan/                # RoomCaptureView integration (iOS LiDAR)
│   ├── Storage/             # Package handling (.roomscan / .housescan), iCloud sync
│   ├── UI/                  # AppTheme (liquid glass), Plan2DView, 3D viewer
│   ├── MacUI/               # macOS menus, print controllers, drag-and-drop
│   └── Resources/           # ibv.svg, AppIcon catalogs, Localizable strings
├── RoomScannerTests/        # Comprehensive unit tests & JSON fixtures
├── .agents/skills/          # Upstream sync automation (sync-upstream-features)
├── docs/                    # GitHub Pages documentation & vector assets
├── project.yml              # XcodeGen project configuration
└── README.md                # Project documentation
```

---

## Upstream Synchronization

This repository includes a specialized skill in [`.agents/skills/sync-upstream-features`](.agents/skills/sync-upstream-features) to selectively merge algorithmic improvements and fixes from upstream while strictly safeguarding:
- Custom branding (**`BabuReddy`**, **`dWalkScan`**, **`ibv.svg`**).
- Custom color palette (`#facc15`, `#fef08a`, `#111110`).
- Liquid glass styling and architectural 2D annotations (opening dimensions & `BRH` parapet heights).

To verify branding compliance at any time:
```bash
python .agents/skills/sync-upstream-features/scripts/sync-upstream.py --check-branding
```

---

## License

This project is licensed under the [MIT License](LICENSE).
