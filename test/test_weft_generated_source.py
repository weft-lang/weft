#!/usr/bin/env python3
"""Generated Weft sources are written and checked in canonical formatter form."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import weft_generated_source as generated


class GeneratedSourceOutput(unittest.TestCase):
    def test_canonical_output_is_the_formatter_form(self):
        template = b"pub(package) fn table_value(index: i64) -> i64 {\nif index == 0 { 1 }\nelse { 2 }\n}\n"
        self.assertEqual(
            generated.canonical(template),
            b"pub(package) fn table_value(index: i64) -> i64 {\n  if index == 0 { 1 }\n  else { 2 }\n}\n",
        )

    def test_canonical_output_is_idempotent(self):
        once = generated.canonical(b"fn f() -> i64 {   42 }\n")
        self.assertEqual(generated.canonical(once), once)

    def test_unparseable_templates_are_rejected(self):
        with self.assertRaises(SystemExit) as raised:
            generated.canonical(b"fn broken( -> i64 { 1 }\n")
        self.assertIn("does not format", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
