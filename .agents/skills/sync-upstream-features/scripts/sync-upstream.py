#!/usr/bin/env python3
"""
sync-upstream.py
Helper tool for safely synchronizing features from upstream repository (vincentlauriat/3DScanner)
into dWalkScan (itsmeBablu/d-walk-scan) while protecting local branding, colors, liquid glass,
and measurement configurations.
"""

import sys
import os
import subprocess
import argparse
import re
from pathlib import Path

UPSTREAM_URL = "https://github.com/vincentlauriat/3DScanner.git"
ORIGIN_URL = "https://github.com/itsmeBablu/d-walk-scan.git"

PROTECTED_PATHS = [
    "RoomScanner/Resources/Assets.xcassets/AppLogo.imageset",
    "RoomScanner/Resources/Assets.xcassets/AppIcon.appiconset",
    "RoomScanner/Resources/Assets.xcassets/AccentColor.colorset",
    "RoomScanner/Resources/ibv.svg",
    "RoomScanner/UI/AppTheme.swift",
    "RoomScanner/Domain/Measurements.swift",
    "RoomScanner/Info-iOS.plist",
    "RoomScanner/Info-macOS.plist",
    "RoomScanner/RoomScanner-iOS.entitlements",
    "RoomScanner/RoomScanner-macOS.entitlements",
    "RoomScanner/RoomScanner-macOS-Release.entitlements",
    "RoomScanner/Resources/Localizable.xcstrings",
    "project.yml",
    "README.md",
    "ARCHITECTURE.md",
    "ARCHITECTURE_EN.md",
    "appcast.xml",
    "docs",
    "release",
    ".github/workflows/ios-unsigned.yml",
    "Scripts/release.sh",
    "Scripts/make-dmg-background.swift",
    "Scripts/make-app-icon.swift",
]

SANITIZATION_RULES = [
    (re.compile(r"Vincent Lauriat", re.IGNORECASE), "BabuReddy"),
    (re.compile(r"vincentlauriat", re.IGNORECASE), "itsmeBablu"),
    (re.compile(r"3DScanner", re.IGNORECASE), "dWalkScan"),
    (re.compile(r"3dscanner", re.IGNORECASE), "dwalkscan"),
    (re.compile(r"io\.github\.vincentlauriat\.3dscanner", re.IGNORECASE), "io.github.itsmebablu.dwalkscan"),
    (re.compile(r"iCloud\.io\.github\.vincentlauriat\.3dscanner", re.IGNORECASE), "iCloud.io.github.itsmebablu.dwalkscan"),
    (re.compile(r"https?://vincentlauriat\.github\.io/3DScanner/?", re.IGNORECASE), "https://github.com/itsmeBablu/d-walk-scan"),
]

def run_git(cmd_args, capture=True, check=True):
    cmd = ["git"] + cmd_args
    try:
        res = subprocess.run(
            cmd,
            stdout=subprocess.PIPE if capture else None,
            stderr=subprocess.PIPE if capture else None,
            text=True,
            check=check,
            encoding="utf-8",
            errors="replace"
        )
        return res.stdout.strip() if capture else ""
    except subprocess.CalledProcessError as e:
        if capture:
            return f"ERROR: {e.stderr.strip()}"
        raise

def ensure_upstream_remote():
    remotes = run_git(["remote", "-v"])
    has_upstream = False
    for line in remotes.splitlines():
        if line.startswith("upstream\t") or line.startswith("upstream "):
            has_upstream = True
            break
    if not has_upstream:
        print(f"[+] Adding upstream remote: {UPSTREAM_URL}")
        run_git(["remote", "add", "upstream", UPSTREAM_URL])
    else:
        print("[✓] Upstream remote already configured.")

def sanitize_text(text: str) -> str:
    res = text
    for pattern, repl in SANITIZATION_RULES:
        res = pattern.sub(repl, res)
    return res

def is_protected(filepath: str) -> bool:
    norm = filepath.replace("\\", "/").strip("/")
    for p in PROTECTED_PATHS:
        p_norm = p.replace("\\", "/").strip("/")
        if norm == p_norm or norm.startswith(p_norm + "/"):
            return True
    return False

def check_branding_compliance():
    """Scans tracked files for forbidden upstream strings."""
    print("--- Scanning Local Working Directory for Upstream Artifacts ---")
    forbidden = [
        re.compile(r"\bvincentlauriat\b", re.IGNORECASE),
        re.compile(r"\bVincent Lauriat\b", re.IGNORECASE),
        re.compile(r"\b3DScanner\b"),
    ]
    
    # Exceptions that might reference upstream intentionally, e.g. skill docs
    allowed_file_prefixes = [
        ".agents/skills/sync-upstream-features",
        ".git",
    ]

    files = run_git(["ls-files"]).splitlines()
    violations = []

    for f in files:
        if any(f.startswith(prefix) for prefix in allowed_file_prefixes):
            continue
        if not os.path.isfile(f):
            continue
        # Skip binaries
        try:
            with open(f, "r", encoding="utf-8", errors="replace") as fh:
                for line_no, line in enumerate(fh, start=1):
                    for pat in forbidden:
                        if pat.search(line):
                            violations.append((f, line_no, line.strip()))
        except Exception:
            pass

    if violations:
        print(f"[!] Found {len(violations)} upstream reference(s) to verify:")
        for f, line_no, line in violations[:20]:
            print(f"  {f}:{line_no} -> {line[:80]}")
        if len(violations) > 20:
            print(f"  ... and {len(violations) - 20} more.")
    else:
        print("[✓] Zero forbidden upstream branding strings detected in tracked source files!")

def status_overview():
    ensure_upstream_remote()
    print("\n--- Fetching Upstream main ---")
    run_git(["fetch", "upstream", "main"], capture=False)

    print("\n--- Inspecting Upstream vs Local Commit Status ---")
    incoming_commits = run_git(["log", "--oneline", "HEAD..upstream/main"]).splitlines()
    if incoming_commits and incoming_commits[0]:
        print(f"[!] {len(incoming_commits)} upstream commit(s) available:")
        for c in incoming_commits[:10]:
            print(f"  * {c}")
        if len(incoming_commits) > 10:
            print(f"  ... and {len(incoming_commits) - 10} more.")
    else:
        print("[✓] Local repository is up to date with upstream/main!")

    print("\n--- Changed Files in Upstream compared to Local ---")
    changed_files = run_git(["diff", "--name-only", "HEAD...upstream/main"]).splitlines()
    features = []
    protected = []

    for f in changed_files:
        if not f:
            continue
        if is_protected(f):
            protected.append(f)
        else:
            features.append(f)

    print(f"Feature / Logic Candidates ({len(features)}):")
    for f in features:
        print(f"  [FEATURE]   {f}")

    print(f"\nProtected Branding / Config Files ({len(protected)}) [NEVER OVERWRITE]:")
    for f in protected:
        print(f"  [PROTECTED] {f}")

def main():
    parser = argparse.ArgumentParser(description="dWalkScan Upstream Synchronization Tool")
    parser.add_argument("--status", action="store_true", help="Check upstream remote and list new commits/files")
    parser.add_argument("--check-branding", action="store_true", help="Scan local files for unwanted upstream strings")
    parser.add_argument("--diff", metavar="COMMIT_OR_BRANCH", help="Show diff for candidate feature file")
    parser.add_argument("--sanitize-diff", metavar="FILE", help="Display sanitized diff for a file against upstream")

    args = parser.parse_args()

    if args.status:
        status_overview()
    elif args.check_branding:
        check_branding_compliance()
    elif args.sanitize_diff:
        ensure_upstream_remote()
        diff = run_git(["diff", "HEAD...upstream/main", "--", args.sanitize_diff])
        print(sanitize_text(diff))
    else:
        status_overview()
        check_branding_compliance()

if __name__ == "__main__":
    main()
