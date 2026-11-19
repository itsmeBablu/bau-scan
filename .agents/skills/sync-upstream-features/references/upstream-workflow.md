# Upstream Synchronization Workflow & Mechanics

This guide outlines the procedural steps for comparing, pulling, and integrating feature commits from `upstream` (`https://github.com/vincentlauriat/3DScanner.git`) into `origin` (`https://github.com/itsmeBablu/d-walk-scan.git`).

---

## 1. Remote Verification

Ensure the `upstream` remote is configured:
```bash
git remote -v
```

If missing:
```bash
git remote add upstream https://github.com/vincentlauriat/3DScanner.git
```

Fetch the latest commits from upstream:
```bash
git fetch upstream main
```

---

## 2. Inspecting Incoming Commits

List commits present in upstream but not in local:
```bash
git log --oneline HEAD..upstream/main
```

Inspect specific commits or author messages:
```bash
git log --stat -n 5 upstream/main
```

---

## 3. Classifying Incoming Changes

Changed files fall into two distinct groups:

### A. Pure Feature / Logic Files (Safe or Candidate for Merge)
- `RoomScanner/Capture/` (LiDAR capture logic, RoomPlan session delegate enhancements)
- `RoomScanner/Export/` (New 3D mesh writers, OBJ/USDZ/GLTF export features, etc.)
- `RoomScanner/Model/` or `RoomScanner/Domain/` (Geometry calculation, floorplan polygons, structural recognition)
- `RoomScannerTests/` (Algorithmic test cases)

### B. Protected Branding / Config Files (DO NOT OVERWRITE)
- Any asset in `Assets.xcassets/`
- Any file in `docs/`
- `project.yml`, `*.plist`, `*.entitlements`
- `AppTheme.swift`, `ibv.svg`
- `README.md`, `ARCHITECTURE*.md`, `appcast.xml`, `release/`

---

## 4. Always Ask Confirmation Rule

Before executing any file update, git cherry-pick, patch application, or commit:
1. Explain what feature or bugfix the upstream commit provides.
2. Show the exact diff or summary of files to be modified.
3. Show any sanitization applied (e.g. converting `3DScanner` references to `dWalkScan`).
4. Ask the user for confirmation:
   - "Apply this feature"
   - "Skip this commit/file"
   - "Customize before applying"

---

## 5. Sanitization Filter

When integrating code snippets or files from upstream, run the automated sanitization rules:

| Pattern | Replacement |
| :--- | :--- |
| `Vincent Lauriat` | `BabuReddy` |
| `vincentlauriat` | `itsmeBablu` |
| `3DScanner` | `dWalkScan` |
| `3dscanner` | `dwalkscan` |
| `io.github.vincentlauriat.3dscanner` | `io.github.itsmebablu.dwalkscan` |
| `iCloud.io.github.vincentlauriat.3dscanner` | `iCloud.io.github.itsmebablu.dwalkscan` |
| `vincentlauriat.github.io/3DScanner` | *(Omit or replace with `github.com/itsmeBablu/d-walk-scan`)* |

Also verify that custom imports (such as `AppTheme`), `.liquidGlass()` modifiers, and millimeter measurement calculations are preserved whenever UI or Export files are touched.
