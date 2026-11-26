import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('compiler_warning_report', Path(__file__).with_name('compiler_warning_report.py'))
warnings = importlib.util.module_from_spec(spec)
with patch.object(sys, 'dont_write_bytecode', True):
    spec.loader.exec_module(warnings)


class WarningReportTests(unittest.TestCase):
    log = '/src/A.swift:4:2: warning: actor isolation\nwarning: build setting ignored\n/src/A.swift:4:2: warning: actor isolation\n/src/B.m:3:1: warning: deprecated\n/src/C.swift:2:1: note: context\n'

    def test_baseline_deduplicates_but_does_not_invent_a_ceiling(self):
        result = warnings.report(self.log)
        self.assertEqual(result['uniqueSwiftWarnings'],1)
        self.assertEqual(result['uniqueBuildWarnings'],3)
        self.assertEqual(result['status'],'baseline-only')
        self.assertIsNone(result['swiftBudget'])

    def test_each_explicit_budget_is_enforced_independently(self):
        self.assertEqual(warnings.report(self.log,0,3)['exceededBudgets'],['swift'])
        self.assertEqual(warnings.report(self.log,1,2)['exceededBudgets'],['build'])
        self.assertEqual(warnings.report(self.log,1,3)['status'],'checked')

    def test_budget_must_be_a_nonnegative_integer_or_blank(self):
        self.assertIsNone(warnings.budget(''))
        self.assertEqual(warnings.budget(' 0 '),0)
        for value in ['-1','1.2','nan','anything']:
            with self.assertRaises(warnings.argparse.ArgumentTypeError):
                warnings.budget(value)


if __name__ == '__main__':
    unittest.main()
