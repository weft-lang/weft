"""Check executable lifetime and exit handling without invoking the compiler."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


RUNNER = Path(os.environ.get("WEFT_MARKDOWN_RUNNER", Path(__file__).with_name("run_markdown_examples.sh"))).resolve()


class MarkdownRunnerTests(unittest.TestCase):
    def run_examples(self, second_exit):
        with tempfile.TemporaryDirectory(prefix="weft-markdown-runner-test-") as directory:
            root = Path(directory)
            compiler = root / "compiler"
            # The stand-in emits executable Python so each running product can
            # report its own inode. This tests the runner's artifact lifecycle.
            compiler.write_text(
                "#!/usr/bin/env python3\n"
                "from pathlib import Path\n"
                "import sys\n"
                "print('#!/usr/bin/env python3')\n"
                "print(''.join(line for line in Path(sys.argv[-1]).read_text().splitlines(True) if not line.startswith('--')))\n"
            )
            compiler.chmod(0o700)
            record = root / "executions.jsonl"
            program = (
                "import json, os\n"
                "from pathlib import Path\n"
                "with Path(os.environ['WEFT_MARKDOWN_TEST_RECORD']).open('a') as output:\n"
                "    output.write(json.dumps({'path': __file__, 'inode': os.stat(__file__).st_ino}) + '\\n')\n"
            )
            document = root / "examples.md"
            document.write_text(
                "```weft run\n" + program + "```\n\n"
                "```weft run\n-- doctest-exit: 7\n" + program + f"raise SystemExit({second_exit})\n```\n\n"
                "```weft test\n" + program + "```\n"
            )
            environment = dict(os.environ, WEFT=str(compiler), WEFT_MARKDOWN_TEST_RECORD=str(record))
            result = subprocess.run(["bash", str(RUNNER), str(document)], env=environment,
                                    text=True, capture_output=True, timeout=30)
            executions = [json.loads(line) for line in record.read_text().splitlines()]
            # Cleanup must remove products on both success and failure.
            for execution in executions:
                self.assertFalse(Path(execution["path"]).exists())
            return result, executions

    def test_each_example_executes_a_distinct_inode(self):
        result, executions = self.run_examples(7)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Markdown example summary: 3 passed, 0 failed", result.stdout)
        self.assertEqual(len(executions), 3)
        self.assertEqual(len({execution["inode"] for execution in executions}), 3)

    def test_unexpected_exit_stops_examples_and_cleans_products(self):
        result, executions = self.run_examples(9)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("expected exit: 7", result.stdout)
        self.assertIn("actual exit: 9", result.stdout)
        self.assertEqual(len(executions), 2)


if __name__ == "__main__":
    unittest.main()
