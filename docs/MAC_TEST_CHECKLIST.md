# dWalkScan macOS Verification Checklist

This manual verification checklist covers testing procedures for the **dWalkScan macOS App** (`RoomScannerMac` scheme) on macOS 15+ Sequoia. All tests are organized by functional domain.

---

## 1. Mouse & Trackpad Gestures
- [ ] **3D Orbiting**: Click and drag inside `ViewerView` to rotate camera smoothly around the center of the model.
- [ ] **3D Zoom**: Pinch on trackpad or scroll with mouse wheel to zoom in and out.
- [ ] **2D Pan**: In 2D Plan view, click and drag to pan across the drawing space.
- [ ] **2D Zoom**: Pinch on trackpad to zoom in/out with CAD grid background adjusting smoothly.
- [ ] **Double-Click Reset**: Double-click on 2D canvas resets zoom and pan back to 100% center.
- [ ] **Hover**: Hovering over buttons and elements reveals native tooltips and help text.
- [ ] **Right-Click Context Menus**:
  - Right-click on sidebar items (Houses, Rooms, Utility Rooms, Designs) shows `Export`, `Reveal in Finder`, and `Delete`.
  - Right-click on design rows includes `Open in new window`.

---

## 2. Keyboard Navigation & Shortcuts
- [ ] **Detail Tabs**:
  - `⌘1`: Switches detail view to **Floor plan** (2D).
  - `⌘2`: Switches detail view to **3D Viewer**.
  - `⌘3`: Switches detail view to **Measurements**.
  - `⌘4`: Switches detail view to **Photos**.
- [ ] **Camera Reset**: `⌘0` resets the 3D camera to default 3/4 framing.
- [ ] **Multi-Level Stepping**:
  - `[`: Steps down one story level (or selects all levels).
  - `]`: Steps up one story level.
- [ ] **Photo Gallery Arrows**:
  - `←` (Left Arrow): Navigates to previous survey photo.
  - `→` (Right Arrow): Navigates to next survey photo.
- [ ] **Design Studio**:
  - `⌘Z`: Undo last object move, rotation, or placement.
  - `⇧⌘Z`: Redo previously undone action.
  - `⌘S`: Saves the current design using coordinated disk write.
  - `⌘A`: Selects all objects on the current floor level.
  - `Delete` / `Backspace`: Deletes currently selected object(s).
  - `←` / `→` / `↑` / `↓`: Nudges selected object by $1\text{ cm}$ ($0.01\text{ m}$) with wall snapping.
  - `⇧` + Arrow keys: Nudges selected object by $10\text{ cm}$ ($0.10\text{ m}$).

---

## 3. Multiple Studio Windows
- [ ] **Independent Windows**: Open multiple design designs simultaneously (`WindowGroup("Design Studio", for: UUID.self)`).
- [ ] **Title & Unsaved Indicator**:
  - Clean state: Window title displays `<Design Name>`.
  - Modified state: Native window edited indicator is enabled; title has no appended bullet.
- [ ] **Menu Focus Binding**: Focused window correctly routes `⌘Z`, `⇧⌘Z`, and `⌘S` via `focusedSceneValue(\.studioSession)` to the active window only.
- [ ] In inspector text fields, Backspace deletes text, arrows move the caret, and Cmd-A selects text. In the viewport, Delete affects objects and arrows move the whole selection in one undo step. Cmd-S writes once. Mac validation pending.
- [ ] **Dirty State Prompt on Close**: Closing a modified window prompts to **Save and close** or **Discard unsaved edits**.
- [ ] Close button, Cmd-W and Cmd-Q: test Save / Discard / Cancel for two dirty windows. Failed save must keep the window open; cancelling quit must keep the application open. Device/Mac validation pending.

---

## 4. Large Scans & Performance
- [ ] **Large Multi-Story House**: Verify memory footprint when viewing a 3+ story building with 15+ rooms.
- [ ] **Photo Streaming**: Verify that large photo batches (50+ photos) stream directly during export without causing high memory spikes.
- [ ] Pending fixes 16/18: export 200 photos, cancel partway, check staging cleanup and measure memory. These fixes are not implemented at this checkpoint.
- [ ] **Mesh Simplification & Junctions**: Wall junctions render cleanly without visual tearing or FPS drops.

---

## 5. iCloud vs. Local Library
- [ ] Toggle iCloud on then off before container resolution finishes. The library must remain local; repeat during slow/offline container access. Mac/device validation pending.
- [ ] Delete a project with a locked/unmovable second package. All previously moved packages and the catalogue must remain intact. A post-commit purge failure can leave `.privacy-trash-<transaction>-<original-name>` beside the package; keep it until deletion/recovery is verified.
- [ ] Force a package save failure: the prior scan must reopen unchanged. Simulate a restart with only the sibling package backup remaining and check recovery.
- [ ] **Local Documents**: Verify packages stored in `~/Documents` are discovered and displayed.
- [ ] **iCloud Container**: Verify synchronization when iCloud Drive container is enabled:
  - Adding a `.housescan` or `.roomscan` file on another device appears in the Mac sidebar.
  - Rename or delete on Mac reflects in iCloud without data loss.
- [ ] **Drag & Drop**: Drag a `.housescan`, `.roomscan`, or `.technicalroom` package from Finder directly into the Mac app window to import.
- [ ] Duplicate house import: both copies reopen, nested room/structure IDs agree, photo links and radiator room references resolve, and raw captured structure, USDZ, thumbnail and other assets are retained. Mac validation pending.

---

## 6. CAD Program & External Exporter Compatibility
- [ ] **Organised Package (ZIP)**:
  - Generate `<Name>_export_<YYYY-MM-DD>.zip`.
  - Extract in Finder: verify structure (`README.txt`, `manifest.json`, `plans/`, `models/`, `photos/`, `studio/`).
- [ ] **AutoCAD / LibreCAD (DXF)**: Open generated `.dxf` in CAD software; verify layers (`WALLS`, `DIMENSIONS`, `DOORS`, `WINDOWS`) and scale.
- [ ] **Blender / Maya (OBJ & USDZ)**:
  - Import `models/model.obj` into Blender; verify normals and clean metric dimensions.
  - Open `models/model.usdz` in macOS Quick Look / Preview.
- [ ] **Photo Index CSV**:
  - Open `photos/index.csv` in Excel or Numbers.
  - Verify headers: `number,level,room,file,timestamp,pos_x,pos_y,pos_z,yaw,pitch,roll`.
  - Verify camera coordinates match scan coordinate space.
