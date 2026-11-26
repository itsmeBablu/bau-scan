import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('audit_swift_concurrency', Path(__file__).with_name('audit_swift_concurrency.py'))
audit = importlib.util.module_from_spec(spec)
with patch.object(sys, 'dont_write_bytecode', True):
    spec.loader.exec_module(audit)


class InventoryTests(unittest.TestCase):
    def test_nested_comments_and_literals_do_not_create_sites(self):
        source = '''// Task.detached @MainActor try?
/* outer /* Task.detached */ try? */
let text = "Task.detached @MainActor try?"
let raw = #"Task.detached \"quoted\" try?"#
let multi = """
Task.detached @MainActor try?
"""
@MainActor func run() { try? work(); Task.detached { work() } }
'''
        sites = audit.inventory(source, 'Fixture.swift')
        self.assertEqual([site['kind'] for site in sites], ['mainActor', 'optionalTry', 'detachedTask'])
        self.assertTrue(all(site['line'] == 8 for site in sites))
        self.assertTrue(all(site['reviewStatus'] == 'review-required' for site in sites))
        self.assertTrue(all(site['owner'] is None for site in sites))

    def test_source_positions_and_whitespace_are_preserved(self):
        source = 'let x = "quoted"\n    Task . detached { try ? work() }\n'
        sites = audit.inventory(source, 'Fixture.swift')
        self.assertEqual([(site['line'],site['column']) for site in sites], [(2,5),(2,23)])
        masked = audit.mask_literals(source)
        self.assertEqual(len(source),len(masked))
        self.assertEqual(source.count('\n'),masked.count('\n'))

    def test_string_interpolation_is_explicitly_not_a_code_analysis(self):
        source = 'let text = "value \\(try? work())"\nlet actual = try? work()'
        sites = audit.inventory(source, 'Fixture.swift')
        self.assertEqual(len(sites),1)
        self.assertEqual(sites[0]['line'],2)


if __name__ == '__main__':
    unittest.main()
