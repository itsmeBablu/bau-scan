---
name: sync-upstream-features
description: >-
  Selectively synchronizes functional features, bug fixes, and algorithmic enhancements
  from the upstream repository (https://github.com/vincentlauriat/3DScanner) into
  dWalkScan (https://github.com/itsmeBablu/d-walk-scan). Strips out upstream owner/author names
  and branding, protects local branding (BabuReddy, dWalkScan, ibv.svg logo), custom colors
  (#facc15, #fef08a, #111110), liquid glass styling, and mm/meters measurements. Always asks
  the user before changing code.
---

# Upstream Feature Synchronization Skill (`sync-upstream-features`)

This skill defines the strict procedure for synchronizing new updates, algorithms, LiDAR/RoomPlan processing improvements, and bug fixes from `https://github.com/vincentlauriat/3DScanner` into `dWalkScan` (`https://github.com/itsmeBablu/d-walk-scan`).

It guarantees that **only functionality is pulled**, while upstream author names, repository branding, logos, color schemes, and configuration are rejected or converted to dWalkScan standards.

---

## Golden Rules

> [!IMPORTANT]
> 1. **Always Ask the User Before Changing Code**: Never cherry-pick, patch, or edit code without presenting the planned changes and getting explicit user approval.
> 2. **Never Overwrite Protected Branding & Styling**: Never overwrite `ibv.svg`, `AppLogo.imageset`, `AppIcon.appiconset`, `AppTheme.swift`, `Measurements.swift`, `project.yml`, `*.plist`, or `*.entitlements`.
> 3. **Sanitize Incoming Code**: Ensure any incoming code referencing `Vincent Lauriat` or `3DScanner` is sanitized to `BabuReddy` and `dWalkScan`.
> 4. **No External Website Redirects**: Keep the repository link pointing to `https://github.com/itsmeBablu/d-walk-scan`. Never redirect to `vincentlauriat.github.io/3DScanner`.

---

## Step 1: Check Upstream Status & Available Commits

Run the helper script to verify remotes, fetch upstream `main`, and inspect incoming commits:

```powershell
python .agents/skills/sync-upstream-features/scripts/sync-upstream.py --status
```

Or execute directly via git:
```powershell
git fetch upstream main
git log --oneline HEAD..upstream/main
```

If there are no new commits on `upstream/main`, inform the user that the local branch is already up to date with upstream.

---

## Step 2: Categorize Changed Files

Classify each changed file into **Feature Candidates** vs **Protected Files**:

### Protected Files (DO NOT OVERWRITE)
Refer to [protected-features.md](./references/protected-features.md):
- `RoomScanner/Resources/ibv.svg`, `docs/assets/ibv.svg`, `docs/ibv.svg`
- `RoomScanner/Resources/Assets.xcassets/AppLogo.imageset/`
- `RoomScanner/Resources/Assets.xcassets/AppIcon.appiconset/`
- `RoomScanner/Resources/Assets.xcassets/AccentColor.colorset/`
- `RoomScanner/UI/AppTheme.swift`
- `RoomScanner/Domain/Measurements.swift`
- `project.yml`, `Info-iOS.plist`, `Info-macOS.plist`
- `RoomScanner-iOS.entitlements`, `RoomScanner-macOS.entitlements`, `RoomScanner-macOS-Release.entitlements`
- `RoomScanner/Resources/Localizable.xcstrings`
- `README.md`, `ARCHITECTURE.md`, `ARCHITECTURE_EN.md`
- `docs/index.html`, `docs/monograph.json`, `appcast.xml`, `release/`

### Feature Candidates (Review & Selectively Pull)
- Algorithmic logic: `RoomScanner/Capture/`, `RoomScanner/Processing/`, `RoomScanner/Domain/`
- Mesh writers & 3D export engines: `RoomScanner/Export/` (preserving `AppTheme` colors and mm/m measurements)
- Unit tests: `RoomScannerTests/` (updating identifiers to match dWalkScan)

---

## Step 3: Inspect Diff & Sanitize Upstream Names

Before proposing any changes to the user, view the sanitized diff:

```powershell
python .agents/skills/sync-upstream-features/scripts/sync-upstream.py --sanitize-diff <path/to/file>
```

Ensure any incoming strings conform to:
- `Vincent Lauriat` → `BabuReddy`
- `vincentlauriat` → `itsmeBablu`
- `3DScanner` → `dWalkScan`
- `3dscanner` → `dwalkscan`
- `io.github.vincentlauriat.3dscanner` → `io.github.itsmebablu.dwalkscan`
- `iCloud.io.github.vincentlauriat.3dscanner` → `iCloud.io.github.itsmebablu.dwalkscan`

---

## Step 4: Ask the User for Approval (MANDATORY)

Present the proposed updates to the user with:
1. **Feature Summary**: What the upstream commit introduces (e.g., improved floor polygon detection, new export format, bugfix for iOS 18).
2. **Impacted Files**: List of files proposed to be modified.
3. **Verification**: Confirmation that local branding, `#facc15` palette, `.liquidGlass()`, and `mm/meters` measurements remain intact.

Use `ask_question` or clear chat prompts to wait for user confirmation before writing or editing any file:
```text
"Upstream commit [abc1234] provides: <feature description>.
Impacted files: <file list>.
Sanitized all author and app branding to BabuReddy / dWalkScan.
Would you like to apply these changes?"
- Yes, apply to working tree
- Skip this update
- Show detailed diff first
```

---

## Step 5: Apply Code Changes Selectively

Once confirmed by the user:
1. Apply the changes cleanly to the target files using `edit_file` or cherry-pick in a temporary staging branch:
   ```powershell
   git cherry-pick -n <commit-hash>
   ```
2. Revert any accidental changes to protected files:
   ```powershell
   git checkout HEAD -- project.yml RoomScanner/UI/AppTheme.swift RoomScanner/Domain/Measurements.swift RoomScanner/Resources/
   ```
3. Run the compliance scan to ensure zero upstream branding strings leaked:
   ```powershell
   python .agents/skills/sync-upstream-features/scripts/sync-upstream.py --check-branding
   ```

---

## Step 6: Post-Sync Verification Checklist

Ensure the following criteria are met before completing the sync:
- [ ] No occurrences of `Vincent Lauriat` or `3DScanner` in newly added or updated files.
- [ ] App logo (`ibv.svg`) and `AppLogo.imageset` remain untouched.
- [ ] Primary yellow (`#facc15`), secondary yellow (`#fef08a`), and dark charcoal (`#111110`) remain active.
- [ ] Liquid glass styling (`.liquidGlass()`, `.liquidGlassCard()`) remains active in UI views.
- [ ] Measurement units support (`mm`, `meters`, and `both`) remains active.
- [ ] In `SettingsView.swift`, the source code link points to `https://github.com/itsmeBablu/d-walk-scan`, and no project website redirect exists.
