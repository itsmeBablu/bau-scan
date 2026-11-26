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
    parser.add_argument("--timeout", type=float, default=120,
                        help="Maximum seconds per subprocess check (default: 120)")
    args = parser.parse_args()
    if not 0 < args.timeout <= 3600:
        parser.error("--timeout must be greater than zero and at most 3600 seconds")
    root = pathlib.Path(__file__).resolve().parents[1]
    evidence = {"commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
                "dirty": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=root, text=True).strip()),
                "timeUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "host": platform.platform(), "python": sys.version, "checks": []}

    def save():
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")

    save()

    def run(name, command):
        if not shutil.which(command[0]):
            evidence["checks"].append({"name": name, "status": "BLOCKED", "reason": command[0] + " unavailable"})
            save()
            return
        check = {"name": name, "status": "RUNNING"}
        evidence["checks"].append(check)
        save()
        try:
            result = subprocess.run(command, cwd=root, text=True, capture_output=True, timeout=args.timeout)
            check.update(status="PASSED" if result.returncode == 0 else "FAILED",
                         exitCode=result.returncode, output=result.stdout + result.stderr)
        except subprocess.TimeoutExpired as error:
            def decode(value):
                return value.decode("utf-8", errors="replace") if isinstance(value, bytes) else value or ""
            check.update(status="FAILED", reason="Check exceeded its time limit", timeoutSeconds=args.timeout,
                         output=decode(error.stdout) + decode(error.stderr))
        except OSError as error:
            check.update(status="BLOCKED", reason=str(error))
        save()

    run("localization", ["node", "Scripts/audit_localization.js", "--strict"])
    run("json-key-regressions", ["node", "--test", "Scripts/test_json_unique_keys.js"])
    run("ui-phase0-source-route", ["node", "--test", "Scripts/test_ui_phase0.js"])
    run("design-system-source", ["node", "--test", "Scripts/test_design_system.js"])
    run("style-ratchet", ["node", "Scripts/audit_styles.js"])
    for suite in ["test_local_quality_baseline.py", "test_swift_concurrency_audit.py", "test_compiler_warning_report.py"]:
        run(suite.removesuffix(".py"), [sys.executable, str(root / "Scripts" / suite)])
    run("service", [sys.executable, "-m", "pytest", "services/technical-google-ai", "-q",
                    "-o", "faulthandler_timeout=" + str(max(1, args.timeout / 2))])
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
    save()
    for check in evidence["checks"]:
        print(check["name"] + ": " + check["status"])
    return 1 if any(c["status"] in ("FAILED", "BLOCKED", "UNVERIFIED") for c in evidence["checks"]) else 0


if __name__ == "__main__":
    raise SystemExit(main())
