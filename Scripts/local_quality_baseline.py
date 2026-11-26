"""Local Phase 0 evidence; never presents static checks as an Apple build."""
import argparse
import datetime
import json
import pathlib
import platform
import plistlib
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parents[1]
    evidence = {"commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
                "dirty": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=root, text=True).strip()),
                "timeUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "host": platform.platform(), "python": sys.version, "checks": []}

    def run(name, command):
        if not shutil.which(command[0]):
            evidence["checks"].append({"name": name, "status": "BLOCKED", "reason": command[0] + " unavailable"})
            return
        result = subprocess.run(command, cwd=root, text=True, capture_output=True)
        evidence["checks"].append({"name": name, "status": "PASSED" if result.returncode == 0 else "FAILED",
                                   "exitCode": result.returncode, "output": result.stdout + result.stderr})

    run("localization", ["node", "Scripts/audit_localization.js", "--strict"])
    run("json-key-regressions", ["node", "--test", "Scripts/test_json_unique_keys.js"])
    run("ui-phase0-source-route", ["node", "--test", "Scripts/test_ui_phase0.js"])
    run("design-system-source", ["node", "--test", "Scripts/test_design_system.js"])
    run("service", [sys.executable, "-m", "pytest", "services/technical-google-ai", "-q"])
    files = list((root / "RoomScanner").rglob("*.plist")) + list((root / "RoomScanner").rglob("*.entitlements")) + list((root / "RoomScanner").rglob("*.xcprivacy"))
    try:
        for file in files:
            with file.open("rb") as stream:
                plistlib.load(stream)
        evidence["checks"].append({"name": "plist-syntax", "status": "PASSED", "files": len(files)})
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        evidence["checks"].append({"name": "plist-syntax", "status": "FAILED", "reason": str(error)})
    run("diff-whitespace", ["git", "diff", "--check"])
    if platform.system() == "Darwin":
        evidence["checks"].append({"name": "Apple-schemes", "status": "UNVERIFIED", "reason": "Run xcodegen generate and Scripts/test.sh all separately; this script does not choose or boot a simulator."})
    else:
        evidence["checks"].append({"name": "Apple-schemes", "status": "BLOCKED", "reason": "Xcode requires macOS. No Apple build or Swift test was run."})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    for check in evidence["checks"]:
        print(check["name"] + ": " + check["status"])
    return 1 if any(c["status"] in ("FAILED", "BLOCKED", "UNVERIFIED") for c in evidence["checks"]) else 0


if __name__ == "__main__":
    raise SystemExit(main())
