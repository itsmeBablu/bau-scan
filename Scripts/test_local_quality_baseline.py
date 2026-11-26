"""Tests for evidence handling, not substitutes for any app/backend checks."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("local_quality_baseline", Path(__file__).with_name("local_quality_baseline.py"))
baseline = importlib.util.module_from_spec(spec)
with patch.object(sys, "dont_write_bytecode", True):
    spec.loader.exec_module(baseline)


class EvidenceTests(unittest.TestCase):
    def run_fixture(self, run):
        directory = Path(__file__).resolve().parents[1] / ".worktrees"
        directory.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=directory) as folder:
            output = Path(folder) / "evidence.json"
            with patch.object(sys, "argv", ["baseline", "--output", str(output), "--timeout", "1"]), \
                 patch.object(baseline.subprocess, "check_output", side_effect=["fixture-sha\n", ""]), \
                 patch.object(baseline.subprocess, "run", side_effect=run), \
                 patch.object(baseline.shutil, "which", return_value="fixture-tool"), \
                 patch.object(baseline.platform, "platform", return_value="fixture-host"), \
                 patch.object(baseline.platform, "system", return_value="Windows"), \
                 contextlib.redirect_stdout(io.StringIO()):
                result = baseline.main()
            return result, json.loads(output.read_text(encoding="utf-8"))

    def test_timeout_keeps_partial_output_and_continues_other_checks(self):
        calls = 0
        def run(command, **kwargs):
            nonlocal calls
            calls += 1
            self.assertEqual(kwargs["timeout"], 1)
            if calls == 1:
                raise subprocess.TimeoutExpired(command, 1, output=b"partial stdout", stderr=b"partial stderr")
            return subprocess.CompletedProcess(command, 0, "ok", "")
        result, evidence = self.run_fixture(run)
        self.assertEqual(result, 1)
        check = evidence["checks"][0]
        self.assertEqual(check["status"], "FAILED")
        self.assertEqual(check["output"], "partial stdoutpartial stderr")
        self.assertEqual(evidence["checks"][1]["status"], "PASSED")
        self.assertEqual(evidence["checks"][-1]["status"], "BLOCKED")
        self.assertFalse(any(item["status"] == "RUNNING" for item in evidence["checks"]))

    def test_process_start_error_is_blocked_not_a_pass(self):
        def run(command, **kwargs):
            raise PermissionError("fixture process denied")
        result, evidence = self.run_fixture(run)
        self.assertEqual(result, 1)
        self.assertEqual(evidence["checks"][0]["status"], "BLOCKED")
        self.assertIn("fixture process denied", evidence["checks"][0]["reason"])
        self.assertEqual(evidence["commit"], "fixture-sha")


if __name__ == "__main__":
    unittest.main()
